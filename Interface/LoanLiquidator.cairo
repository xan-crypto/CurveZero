####################################################################################
# @title LoanLiquidator contract
# @dev all numbers passed into contract must be Math10xx8 type
# Loan liquidators can
# - call liquidate on a loan/user, if valid call the loan gets liquidated and liquidation fee paid to the caller
# liquidation fee is set at 5% of the liquidated amount
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_in_range, is_le
from starkware.cairo.common.math import assert_le, assert_not_zero
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle, CapitalBorrower
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add, Math10xx8_one, Math10xx8_convert_from, Math10xx8_convert_to, Math10xx8_ts
from Functions.Checks import check_is_owner, check_user_balance, calc_residual_loan_capital, check_user_loan, calc_loan_outstanding, calc_accrued_interest_payments, loan_not_valid_liquidation

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
# we emit the event in the same format as the CB events to make data consumption consistent for the off chain LL
# recall the loan book is monitored by all liquidators looking for liquidation opportunities
# we also have a separate emit for liquidation details which includes who the liquidator was, and what the level of insolvency was
# type 1 - no loss, type 2 - interest loss only, type 3 - interest and capital loss
####################################################################################
@event
func event_ll_loan_book(addy : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt):
end
@event
func event_ll_loan_liquidate(liquidator : felt, addy : felt, notional : felt, type : felt, interest_loss : felt, capital_loss):
end

####################################################################################
# @dev liquidator can call liquidate loan
# we need to design the liquidator to allow a LL with $10k USDC to partially liquidate a $1mil USDC loan
# we need this for capital efficiency since its unlikely that someone will leave $1mil USDC idle waiting to liquidate the above in one go
# instead liquidation should be an iterative process, with a final bespoke fn at the end for residual flows
# firstly a loan is valid for liquidation if collateral value <= total accrued notional os (notional + accrued interest + hist accrual - repayments) x liquidation ratio
# secondly if end ts + grace period < current time
# thirdly if the user loan has the liquidate me flag set to 1
# -------
# Next the LL should indicate the amount of USDC he wants to liquidate 
# there are 2 possible paths initially
# if LL amount >= total accrued notional os or LL amount + fee >= collateral value -> then final liquidation
# if not above -> then partial liquidation similar to a loan repayment and collateral decrease
# -------
# Next the final liquidation has 3 paths
# option 1 - total accrued notional os + liquidation fee <= value of collateral  
# - no capital loss no accrued interest loss
# - excess colateral can be returned back to the user
# - loan total reduces by the residual loan notional actually given to user NB NB (loan total is cashflow out of protocol)
# - accrued interest + hist accrual is distributed to LP/IF/GT
# option 2 - residual loan notional + liquidation fee <= value of collateral < toal accrued notional os + liquidation fee
# - no capital loss actual accrued interest loss, LPs lose some of the accrued interest earned but not actual capital
# - no collateral remains, user gets nothing back
# - loan total reduces by the residual loan notional
# - USDC returned - residual loan notional gets added to the capital total with no distribution to others
# option 3 - 0 <= value of collateral < residual loan notional + liquidation fee
# - actual capital loss actual accrued interest loss
# - no collateral remains, user gets nothing back
# - loan total reduces by the residual loan notional
# - residual loan notional - USDC received gets sub from the capital total, actual capital loss captured here
# - residual loan notional - USDC received gets added to the insolvency total, this is the number that needs to be repaid to make LPs whole on capital
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
    let (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, accrued_interest) = CapitalBorrower.view_loan_detail(cb_addy, user)
    check_user_loan(notional)
    
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
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
    let (total_acrrued_notional_os) = calc_loan_outstanding(notional, accrued_interest, hist_accrual, hist_repay)
    let (total_acrrued_notional_os_lr) = Math10xx8_mul(total_acrrued_notional_os, liquidation_ratio)
    let (price_erc) = Oracle.get_oracle_price(oracle_addy)
    let (decimals) = Oracle.get_oracle_decimals(oracle_addy)
    let (price) = Math10xx8_convert_to(price_erc, decimals)
    let (collateral_value) = Math10xx8_mul(price, collateral)

    # @dev check liquidation conditions
    # valid for liquidation if the value of the collateral is below the total accrued notional os x liquidation ratio 
    # or if the current ts > end ts + grace period
    # or if liquidate me flag set to 1
    let (liquidation_cond1) = is_le(collateral_value, total_acrrued_notional_os_lr)
    let (liquidation_cond2) = is_le(grace_period_end, block_ts)
    let liquidation_cond3 = liquidate_me
    tempvar should_liquidate = liquidation_cond1 + liquidation_cond2 + liquidation_cond3

    if should_liquidate != 0:
        # @dev now check if its a partial liquidation or final liquidation
        let (liquidation_fee) = Settings.get_weth_liquidation_fee(settings_addy)
        let (one) = Math10xx8_one()
        let (one_plus_liquidation_fee) = Math10xx8_add(one, liquidation_fee)
        let (amount_liquidation_fee) = Math10xx8_mul(amount, one_plus_liquidation_fee)
        
        # @dev other data required
        let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
        let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
        let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
        
        # @dev check if final liquidation
        let (final_cond1) = is_le(total_acrrued_notional_os, amount)
        let (final_cond2) = is_le(collateral_value, amount_liquidation_fee)
        tempvar is_final = final_cond1 + final_cond2
        
        if is_final != 0:
            # @dev final liquidation process            
            let (residual_loan_capital) = calc_residual_loan_capital(notional, hist_repay, notional)
            let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
            CZCore.set_update_rate(czcore_addy, residual_loan_capital, rate, 0)
            CZCore.set_reduce_accrual(czcore_addy, total_accrual)

            let (residual_loan_capital_lf) = Math10xx8_mul(residual_loan_capital, one_plus_liquidation_fee)
            let (total_acrrued_notional_os_lf) = Math10xx8_mul(total_acrrued_notional_os, one_plus_liquidation_fee)
            let (new_loan_total) = Math10xx8_sub(loan_total, residual_loan_capital)
            
            # dev liquidation process
            let (test_option1) = is_le(total_acrrued_notional_os_lf, collateral_value)
            let (test_option2) = is_in_range(collateral_value, residual_loan_capital_lf, total_acrrued_notional_os_lf)

            if (test_option1) == 1:
                # @dev receive the USDC
                let ll_amount_receive = total_acrrued_notional_os
                check_user_balance(usdc_addy, liquidator, ll_amount_receive)
                CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive)
                # send the WETH
                let (ll_amount_send) = Math10xx8_div(total_acrrued_notional_os_lf, price)
                CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send)
                # send remaining collateral to user
                let (collateral_balance) = Math10xx8_sub(collateral, ll_amount_send)
                CZCore.erc20_transfer(czcore_addy, weth_addy, user, collateral_balance)
                # distribute the total accrual 
                let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
                let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
                let (accrued_interest_lp, accrued_interest_if, accrued_interest_gt) = calc_accrued_interest_payments(total_accrual, lp_split, if_split, gt_split)
                CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, accrued_interest_if)
                # @dev update CZCore and loan  
                let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
                let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)
                CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, new_reward_total)
                CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                event_ll_loan_book.emit(user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                event_ll_loan_liquidate.emit(liquidator, user, total_acrrued_notional_os, 1, 0, 0)
                return()
            else:      

                # receive the USDC
                let (ll_amount_receive) = Math10xx8_div(collateral_value, one_plus_liquidation_fee)
                check_user_balance(usdc_addy, liquidator, ll_amount_receive)
                CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive)
                # send the WETH
                CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, collateral)
                let (total_loss) = Math10xx8_sub(total_acrrued_notional_os, ll_amount_receive)

                # @dev update CZCore and loan  
                if (test_option2) == 1:
                    let (residual) = Math10xx8_sub(ll_amount_receive, residual_loan_capital)
                    let (new_capital_total) = Math10xx8_add(capital_total, residual)
                    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, reward_total)
                    CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_ll_loan_book.emit(user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_ll_loan_liquidate.emit(liquidator, user, total_acrrued_notional_os, 2, total_loss, 0)
                    return()
                else:
                    let (residual) = Math10xx8_sub(residual_loan_capital, ll_amount_receive)
                    let (new_capital_total) = Math10xx8_sub(capital_total, residual)
                    let (new_insolvency_total) = Math10xx8_add(insolvency_total, residual)
                    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, new_insolvency_total, reward_total)
                    CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_ll_loan_book.emit(user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    event_ll_loan_liquidate.emit(liquidator, user, total_acrrued_notional_os, 3, total_loss-residual, residual)
                    return()
                end
            end
       
        else:       
            # @dev partial liquidation process
            let (residual_loan_capital) = calc_residual_loan_capital(notional, hist_repay, amount)
            let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
            CZCore.set_update_rate(czcore_addy, residual_loan_capital, rate, 0)

            # receive the USDC
            let ll_amount_receive = amount
            check_user_balance(usdc_addy, liquidator, ll_amount_receive)
            CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive)
            # @dev send the WETH
            let (ll_amount_send) = Math10xx8_div(amount_liquidation_fee, price)
            CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send)
            # @dev update user loan  
            let (new_repay) = Math10xx8_add(hist_repay, amount)
            let (new_collateral) = Math10xx8_sub(collateral, ll_amount_send)
            CZCore.set_cb_loan(czcore_addy, user, notional, new_collateral, start_ts, block_ts, end_ts, rate, total_accrual, new_repay, liquidate_me, 0)            
            # @dev update cz state
            let (new_loan_total) = Math10xx8_sub(loan_total, residual_loan_capital)
            CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
            event_ll_loan_book.emit(user, notional, new_collateral, start_ts, block_ts, end_ts, rate, total_accrual, new_repay, liquidate_me)
            event_ll_loan_liquidate.emit(liquidator, user, amount, 0, 0, 0)
            return()
        end
        
    else:
        # @dev liquidation not valid throw error
        loan_not_valid_liquidation()
        return()
    end
end
