####################################################################################
# @title LoanLiquidator contract
# @dev all numbers passed into contract must be Math10xx8 type
# Loan liquidators can
# - call liquidate on a loan/user, if valid call the loan gets liquidated and liquidation fee paid to the caller
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_nn, assert_nn_le
from starkware.cairo.common.math_cmp import is_in_range
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle, CapitalBorrower
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_pow_frac, Math10xx8_sub, Math10xx8_add, Math10xx8_ts, Math10xx8_one, Math10xx8_year, Math10xx8_convert_from, Math10xx8_zero
from Functions.Checks import check_is_owner, check_min_pp, check_ltv, check_utilization, check_max_term, check_loan_range, check_user_balance

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
# recall the loan book is monitored by all liquidators looking for liquidation opportunities
####################################################################################
@event
func event_loan_liquidate(addy : felt):
end

####################################################################################
# @dev liquidator can call liquidate loan
# 
# @param input is 
# - the user addy whose loan is to be liquidated
####################################################################################
@external
func liquidate_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt):
    alloc_locals
    # @dev check if user has a loan
    let (_trusted_addy) = trusted_addy.read()
    let (liquidator) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (cb_addy) = TrustedAddy.get_cb_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual, accrued_interest) = CapitalBorrower.view_loan_detail(cb_addy, user)
    with_attr error_message("User does not have an existing loan to repay."):
        assert has_loan = 1
    end
    # @dev check loan is below the liquidation ratio
    let (liquidation_ratio) = Settings.get_weth_liquidation_ratio(settings_addy)
    let (liquidation_fee) = Settings.get_weth_liquidation_fee(settings_addy)
    let (one) = Math10xx8_one()
    let (one_plus_liquidation_fee) = Math10xx8_add(one,liquidation_fee)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    let (price_erc) = Oracle.get_oracle_price(oracle_addy)
    let (decimals) = Oracle.get_oracle_decimals(oracle_addy)
    let (price) = Math10xx8_convert_to(price_erc, decimals)
    let (value_collateral) = Math10xx8_mul(price, collateral)
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    let (an_liquidation_ratio) = Math10xx8_mul(acrrued_notional, liquidation_ratio)
    let (an_liquidation_fee) = Math10xx8_mul(acrrued_notional, one_plus_liquidation_fee)
    let (cashflow) = Math10xx8_sub(notional, hist_accrual)
    let (n_liquidation_fee) = Math10xx8_mul(cashflow, one_plus_liquidation_fee)
    with_attr error_message("Loan is not valid for liquidation."):
        assert_le(value_collateral, an_liquidation_ratio)
    end
    
    # test 
    let (test1) = is_in_range(value_collateral, n_liquidation_fee, an_liquidation_fee)
    let (test2) = is_in_range(value_collateral, an_liquidation_fee, an_liquidation_ratio)
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    
    if (test2) == 1:
        let (ll_amount_receive) = acrrued_notional
        let (ll_amount_receive_erc) = check_user_balance(liquidator, usdc_addy, ll_amount_receive)
        CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive_erc)
        
        let (ll_amount_send) = Math10xx8_div(an_liquidation_fee,price)
        let (ll_amount_send_erc) = check_user_balance(czcore_addy, weth_addy, ll_amount_send)
        CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send_erc)
        
        let (collateral_balance) = Math10xx8_sub(collateral,ll_amount_send)
        let (collateral_balance_erc) = check_user_balance(czcore_addy, weth_addy, collateral_balance)
        CZCore.erc20_transfer(czcore_addy, weth_addy, user, collateral_balance_erc)
        
        let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
        let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
        let (accrued_interest_lp) = Math10xx8_mul(lp_split, total_accrual)
        let (accrued_interest_if) = Math10xx8_mul(if_split, total_accrual)
        let (accrued_interest_gt) = Math10xx8_mul(gt_split, total_accrual)
        let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
        let (accrued_interest_if_erc) = Math10xx8_convert_from(accrued_interest_if, usdc_decimals) 
        CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, accrued_interest_if_erc)
        # @dev update CZCore and loan  
        let (new_loan_total1) = Math10xx8_add(loan_total, hist_accrual)
        let (new_loan_total2) = Math10xx8_sub(new_loan_total1, notional)
        let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
        let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)
        CZCore.set_captal_loan_reward_total(czcore_addy, new_capital_total, new_loan_total2, new_reward_total)
        CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0)
        return()
    else:
        if (test1) == 1:
        
                let (ll_amount_receive1) = Math10xx8_mul(collateral,price)
                let (ll_amount_receive2) = Math10xx8_div(ll_amount_receive1,one_plus_liquidation_fee)
                let (ll_amount_receive_erc) = check_user_balance(liquidator, usdc_addy, ll_amount_receive2)
                CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive_erc)

                let (ll_amount_send_erc) = check_user_balance(czcore_addy, weth_addy, collateral)
                CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send_erc)

                # @dev update CZCore and loan  
                let (new_loan_total1) = Math10xx8_add(loan_total, hist_accrual)
                let (new_loan_total2) = Math10xx8_sub(new_loan_total1, notional)
                
                let (a) = Math10xx8_sub(notional,hist_accrual)
                let (b) = Math10xx8_sub(ll_amount_receive2,a)
                let (new_capital_total) = Math10xx8_add(capital_total, b)
                CZCore.set_captal_loan_reward_total(czcore_addy, new_capital_total, new_loan_total2, reward_total)
                CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0)


            return()
        else:
                let (ll_amount_receive1) = Math10xx8_mul(collateral,price)
                let (ll_amount_receive2) = Math10xx8_div(ll_amount_receive1,one_plus_liquidation_fee)
                let (ll_amount_receive_erc) = check_user_balance(liquidator, usdc_addy, ll_amount_receive2)
                CZCore.erc20_transferFrom(czcore_addy, usdc_addy, liquidator, czcore_addy, ll_amount_receive_erc)

                let (ll_amount_send_erc) = check_user_balance(czcore_addy, weth_addy, collateral)
                CZCore.erc20_transfer(czcore_addy, weth_addy, liquidator, ll_amount_send_erc)

                # @dev update CZCore and loan  
                let (new_loan_total1) = Math10xx8_add(loan_total, hist_accrual)
                let (new_loan_total2) = Math10xx8_sub(new_loan_total1, notional)
                
                let (a) = Math10xx8_sub(notional,hist_accrual)
                let (b) = Math10xx8_sub(a,ll_amount_receive2)
                let (new_capital_total) = Math10xx8_sub(capital_total, b)
                CZCore.set_captal_loan_reward_total(czcore_addy, new_capital_total, new_loan_total2, reward_total)
                CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0)
                CZCore.set_insolvency(czcore_addy, b)
        
            return()
        end
    
    
    # @dev transfer WETH to liquidator with fee (accrued notional*1.025/weth price), 
    # and receive accrued notional in USDC from liquidator
    # calc weth to be sent to liquidator
    
