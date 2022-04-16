####################################################################################
# @title LoanLiquidator contract
# @dev all numbers passed into contract must be Math10xx8 type
# Loan liquidators can
# - call liquidate on a loan/user, if valid call the loan gets liquidated and liquidation fee paid to the caller
# liquidation fee is set at 2.5% of the liquidated notional
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_in_range, is_le
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle, CapitalBorrower
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add, Math10xx8_one, Math10xx8_convert_from, Math10xx8_convert_to, Math10xx8_ts
from Functions.Checks import check_is_owner, check_user_balance

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
# this allows for upgradability of this contract
####################################################################################
@storage_var
func owner_addy() -> (addy : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    owner_addy.write(owner)
    return ()
end

@view
func get_owner_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = owner_addy.read()
    return (addy)
end

####################################################################################
# @dev storage for the trusted addy contract
# the TrustedAddy contract stores all the contract addys
####################################################################################
@storage_var
func trusted_addy() -> (addy : felt):
end

@view
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = trusted_addy.read()
    return (addy)
end

@external
func set_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    trusted_addy.write(addy)
    return ()
end

####################################################################################
# @dev emit LL events to build/maintain the loan book for liquidation/monitoring/dashboard
# all we need to emit is the user addy that got liquidated, we can then remove this loan from the loan book
# we emit the event in the same format as the CB events to make data consumption consistent for the off chain LL
# recall the loan book is monitored by all liquidators looking for liquidation opportunities
# we also have a separate emit for liquidation details which includes who the liquidator was, and what the level of insolvency was
# type 1 - no loss, type 2 - interest loss only, type 3 - interest and capital loss
####################################################################################
@event
func event_loan_liquidate(addy : felt, has_loan : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt):
end
@event
func event_liquidate_details(liquidator : felt, addy : felt, notional : felt, type : felt, interest_loss : felt, capital_loss):
end

####################################################################################
# @dev liquidator can call liquidate loan
# we need to redesign the liquidator to allow a LL with $10k USDC to partially liquidate a $1mil USDC loan
# we need this for capital efficiency since its unlikely that someone will leave $1mil USDC idle waiting to liquidate the above in one go
# instead liquidation should be an iterative process, with a final bespoke fn at the end for residual flows
# firstly a loan is valid for liquidation if collateral value <= accrued notional x liquidation ratio or
# secondly if end ts + grace period < current time
# -------
# Next the LL should indicate the amount of USDC he wants to liquidate 
# there are 2 possible paths initially
# if LL amount >= Accrued notional or LL amount + fee >= collateral value -> then final liquidation
# if not above -> then partial liquidation similar to a loan repayment and collateral decrease
# -------
# Next the final liquidation has 3 paths
# option 1 - accrued notional + liquidation fee <= value of collateral  
# - no capital loss no accrued interest loss
# - excess colateral can be returned back to the user
# - loan total reduces by the cashflow actually given to user NB NB (loan total is cashflow out of protocol)
# - accrued interest + hist accrual is distributed to LP/IF/GT
# option 2 - cashflow + liquidation fee <= value of collateral < accrued notional + liquidation fee
# - no capital loss actual accrued interest loss, LPs lose some of the accrued interest earned but not actual capital
# - no collateral remains, user gets nothing back
# - loan total reduces by the cashflow actually given to user
# - USDC returned - cashflow gets added to the capital total with no distribution to others
# option 3 - 0 <= value of collateral < cashflow + liquidation fee
# - actual capital loss actual accrued interest loss
# - no collateral remains, user gets nothing back
# - loan total reduces by the cashflow actually given to user
# - cashflow - USDC received gets sub from the capital total, actual capital loss captured here
# - cashflow - USDC received gets added to the insolvency total, this is the number that needs to be repaid to make LPs whole
# @param input is 
# - the user addy whose loan is to be liquidated
# - the USDC amount to liquidate
####################################################################################
@external
func liquidate_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, amount : felt):
    alloc_locals
    # @dev check if user has a loan
    let (_trusted_addy) = trusted_addy.read()
    let (cb_addy) = TrustedAddy.get_cb_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, accrued_interest) = CapitalBorrower.view_loan_detail(cb_addy, user)
    with_attr error_message("User does not have an existing loan to liquidate."):
        assert has_loan = 1
    end
    
    # @dev get all the required addys
    let (liquidator) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    
    # @dev check that the loan is valid for liqudiation
    let (block_ts) = Math10xx8_ts()
    let (grace_period) = Settings.get_grace_period(settings_addy)
    let (grace_period_end) = Math10xx8_add(grace_period, end_ts)
    let (liquidation_ratio) = Settings.get_weth_liquidation_ratio(settings_addy)
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    let (accrued_notional_liquidation_ratio) = Math10xx8_mul(acrrued_notional, liquidation_ratio)
    let (price_erc) = Oracle.get_oracle_price(oracle_addy)
    let (decimals) = Oracle.get_oracle_decimals(oracle_addy)
    let (price) = Math10xx8_convert_to(price_erc, decimals)
    let (collateral_value) = Math10xx8_mul(price, collateral)

    # @dev check liquidation conditions
    # valid for liquidation if the value of the collateral is below the accrued notional x liquidation ratio 
    # or if the current ts > end ts + grace period
    let (liquidation_cond1) = is_le(collateral_value, accrued_notional_liquidation_ratio)
    let (liquidation_cond2) = is_le(grace_period_end, block_ts)
    tempvar should_liquidate = liquidation_cond1 + liquidation_cond2

    if should_liquidate != 0:
        # @dev now check if its a partial liquidation or final liquidation
        let (liquidation_fee) = Settings.get_weth_liquidation_fee(settings_addy)
        let (one) = Math10xx8_one()
        let (one_plus_liquidation_fee) = Math10xx8_add(one, liquidation_fee)
        let (amount_liquidation_fee) = Math10xx8_mul(amount, one_plus_liquidation_fee)
        
        # @dev other data required
        let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
        let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
        let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
        let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
        
        # @dev check if final liquidation
        let (final_cond1) = is_le(acrrued_notional, amount)
        let (final_cond2) = is_le(collateral_value, amount_liquidation_fee)
        tempvar is_final = final_cond1 + final_cond2
        
        if is_final != 0:
            # @dev final liquidation process            
            let (loan_cashflow) = Math10xx8_sub(acrrued_notional, total_accrual)
            let (loan_cashflow_liquidation_fee) = Math10xx8_mul(loan_cashflow, one_plus_liquidation_fee)
            let (accrued_notional_liquidation_fee) = Math10xx8_mul(acrrued_notional, one_plus_liquidation_fee)
            let (new_loan_total) = Math10xx8_sub(loan_total, loan_cashflow)
            
            # dev liquidation process
            let (test_option1) = is_le(accrued_notional_liquidation_fee, collateral_value)
            let (test_option2) = is_in_range(collateral_value, loan_cashflow_liquidation_fee, accrued_notional_liquidation_fee)

            if (test_option1) == 1:
                # @dev receive the USDC
                let ll_amount_receive = acrrued_notional
                let (ll_amount_receive_erc) = check_user_balance(liquidator, usdc_addy, ll_amount_receive)
                CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive_erc)
                # send the WETH
                let (ll_amount_send) = Math10xx8_div(accrued_notional_liquidation_fee,price)
                let (ll_amount_send_erc) = check_user_balance(czcore_addy, weth_addy, ll_amount_send)
                CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send_erc)
                # send remaining collateral to user
                let (collateral_balance) = Math10xx8_sub(collateral,ll_amount_send)
                let (collateral_balance_erc) = check_user_balance(czcore_addy, weth_addy, collateral_balance)
                CZCore.erc20_transfer(czcore_addy, weth_addy, user, collateral_balance_erc)
                # distribute the total accrual 
                let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
                let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
                let (accrued_interest_lp) = Math10xx8_mul(lp_split, total_accrual)
                let (accrued_interest_if) = Math10xx8_mul(if_split, total_accrual)
                let (accrued_interest_gt) = Math10xx8_mul(gt_split, total_accrual)
                let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
                let (accrued_interest_if_erc) = Math10xx8_convert_from(accrued_interest_if, usdc_decimals) 
                CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, accrued_interest_if_erc)
                # @dev update CZCore and loan  
                let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
                let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)
                CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, new_reward_total)
                CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                event_loan_liquidate.emit(user, 0, 0, 0, 0, 0, 0, 0, 0)
                event_liquidate_details.emit(liquidator, user, acrrued_notional, 1, 0, 0)
                return()
            else:      

                # receive the USDC
                let (ll_amount_receive) = Math10xx8_div(collateral_value, one_plus_liquidation_fee)
                let (ll_amount_receive_erc) = check_user_balance(liquidator, usdc_addy, ll_amount_receive)
                CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive_erc)
                # send the WETH
                let (ll_amount_send_erc) = check_user_balance(czcore_addy, weth_addy, collateral)
                CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send_erc)
                let (total_loss) = Math10xx8_sub(acrrued_notional, ll_amount_receive)

                # @dev update CZCore and loan  
                if (test_option2) == 1:
                    let (residual) = Math10xx8_sub(ll_amount_receive, loan_cashflow)
                    let (new_capital_total) = Math10xx8_add(capital_total, residual)
                    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, reward_total)
                    CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_loan_liquidate.emit(user, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_liquidate_details.emit(liquidator, user, acrrued_notional, 2, total_loss, 0)
                    return()
                else:
                    let (residual) = Math10xx8_sub(loan_cashflow, ll_amount_receive)
                    let (new_capital_total) = Math10xx8_sub(capital_total, residual)
                    let (new_insolvency_total) = Math10xx8_add(insolvency_total, residual)
                    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, new_insolvency_total, reward_total)
                    CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_loan_liquidate.emit(user, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_liquidate_details.emit(liquidator, user, acrrued_notional, 3, total_loss-residual, residual)
                    return()
                end
            end
       
        else:       
            # @dev partial liquidation process
            # receive the USDC
            let ll_amount_receive = amount
            let (ll_amount_receive_erc) = check_user_balance(liquidator, usdc_addy, ll_amount_receive)
            CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive_erc)
            # @dev send the WETH
            let (ll_amount_send) = Math10xx8_div(amount_liquidation_fee, price)
            let (ll_amount_send_erc) = check_user_balance(czcore_addy, weth_addy, ll_amount_send)
            CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send_erc)
            # @dev update user loan  
            let (new_notional) = Math10xx8_sub(acrrued_notional, amount)
            let (new_collateral) = Math10xx8_sub(collateral, ll_amount_send)
            CZCore.set_cb_loan(czcore_addy, user, has_loan, new_notional, new_collateral, start_ts, block_ts, end_ts, rate, total_accrual, 0)            
            # @dev update cz state
            let (new_loan_total) = Math10xx8_sub(loan_total, amount)
            CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
            event_loan_liquidate.emit(user, has_loan, new_notional, new_collateral, start_ts, block_ts, end_ts, rate, total_accrual)
            event_liquidate_details.emit(liquidator, user, amount, 1, 0, 0)
            return()
        end
        
    else:
        # @dev liquidation not valid throw error
        with_attr error_message("Loan is not valid for liquidation."):
            assert 0 = 1
        end
        return()
    end
end
