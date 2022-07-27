####################################################################################
# @title CapitalBorrower contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - view their current loan if any including the accrued interest to current block timestamp
# - create a USD loan in return for collateral (USDC vs WETH initially)
# - increase their collateral for the loan
# - decrease their collateral for the loan subject to LTV setting within the Settings contract
# - make a partial repayment of the loan
# - make a full repayment of the loan (needed because full repayment depends on block timestamp)
# - refinance or roll the loan, i.e. increase the notional needed and/or change the end date
# - flag loan for liquidation in the case they cannot repay and want to close the loan now
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle, PriceProvider
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add, Math10xx8_ts, Math10xx8_one, Math10xx8_year
from Functions.Checks import check_is_owner, check_ltv, check_utilization, check_max_term, check_loan_range, check_user_balance, calc_residual_loan_capital, calc_accrued_interest_payments, check_no_loan, check_user_loan, check_repayment_amount, check_collateral_withdraw, check_notional_collateral, calc_loan_outstanding

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
# @dev emit CB events to build/maintain the loan book for liquidation/monitoring/dashboard
# event cb loan book is for loan book building and should always be the latest state of the loan for a particular user
# event cb loan change captures data for frontend UX
####################################################################################
@event
func event_cb_loan_book(addy : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt):
end
@event
func event_cb_loan_change(addy : felt, amount : felt, loan_os : felt, type : felt):
end

####################################################################################
# @dev query a users loan details + accrued interest at current block ts
# @param input is 
# - the addy of the user in question
# @return 
# - the notional of the loan in USDC, including any origination fees at initiation  
# - the collateral in WETH that backs this loan
# - the start timestamp when the loan was taken (partial repayment does not affect this date, refinancing does tho) - used for UX
# - the revaluation timestamp (either the loan start date or the last repayment or the last refinancing)
# - the end timestamp
# - the rate at which the loan was set (quoted and stored as simple interest)
# - the historical accrual which is needed for cashflow vs loan recon, if a loan is changed, this records the historical accrual prior to change
# so that the correct fees can be paid to the LP/IF/GT when the loan is closed out
# - the total repayments made to date
# so loan amount o/s = notional + accrued interest + hist accrual - repayment
# - the liquidate me flag, for users that cant repay the loan and want to exit position now
# - the accrued interest from reval to current block timestamp on the max(Notional - Repayment, 0)
# recall with simple interest there is no interest on interest (the compounding is implicitly included in the rate)
####################################################################################
@view
func view_loan_detail{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
        notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt, accrued_interest : felt):
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me) = CZCore.get_cb_loan(czcore_addy, user)
    let (block_ts) = Math10xx8_ts()
    let (one) = Math10xx8_one()
    let (year_secs) = Math10xx8_year()

    # @dev calc accrued interest and return loan details
    if notional == 0:
        return (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, 0)
    else:
        let (test_notional_os) = is_le(hist_repay, notional)
        if test_notional_os == 1:
            let (notional_os) = Math10xx8_sub(notional, hist_repay)
            let (diff_ts) = Math10xx8_sub(block_ts, reval_ts)
            let (year_frac) = Math10xx8_div(diff_ts, year_secs)
            let (rate_year_frac) = Math10xx8_mul(rate, year_frac)
            let (accrued_interest) = Math10xx8_mul(notional_os, rate_year_frac)
            return (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, accrued_interest)
        else:
            return (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, 0)
        end
    end
end

####################################################################################
# @dev create a new loan for a user
# @param input is 
# - the notional of the loan in USDC
# - the collateral of the loan in WETH
# - the end date of the loan in timestamp
####################################################################################
@external
func create_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(notional : felt, collateral : felt, end_ts : felt):
    alloc_locals
    # @dev addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (pp_addy) = TrustedAddy.get_pp_addy(_trusted_addy)
    check_no_loan(czcore_addy, user)
   
    # @dev checks
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, notional, collateral)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    check_user_balance(weth_addy, user, collateral)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_utilization(settings_addy, notional, loan_total, capital_total)
    let (start_ts) = Math10xx8_ts()
    check_max_term(settings_addy, start_ts, end_ts)
    check_loan_range(settings_addy, notional)

    # @dev lp yield boost is set by governance and is effectively a parallel shift of the curve upward to balance supply demand / attract lp capital
    let (rate) = PriceProvider.get_rate(pp_addy, end_ts)
    let (lp_yield_boost) = Settings.get_lp_yield_boost(settings_addy)
    let (rate_boost) = Math10xx8_add(rate, lp_yield_boost)

    # @dev add origination fee
    let (fee, df_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (df_addy) = TrustedAddy.get_df_addy(_trusted_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (one) = Math10xx8_one()
    let (one_plus_fee) = Math10xx8_add(one, fee)
    let (notional_with_fee) = Math10xx8_mul(one_plus_fee, notional)
    let (origination_fee) = Math10xx8_sub(notional_with_fee, notional)

    # @dev calc amounts to transfer 
    let (df_fee) = Math10xx8_mul(origination_fee, df_split)
    let (if_fee) =  Math10xx8_mul(origination_fee, if_split)
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)

    # @dev all transfers
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, notional)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, df_addy, df_fee)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, if_fee)      

    # @dev update CZCore - run accrual + update wt avg rate
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    CZCore.set_update_rate(czcore_addy, notional_with_fee, rate_boost, 1)
    CZCore.set_cb_loan(czcore_addy, user, notional_with_fee, collateral, start_ts, start_ts, end_ts, rate_boost, 0, 0, 0, 1)
    let (new_loan_total) = Math10xx8_add(loan_total, notional_with_fee)
    CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
    
    # @dev emit event
    event_cb_loan_book.emit(user, notional_with_fee, collateral, start_ts, start_ts, end_ts, rate_boost, 0, 0, 0)
    event_cb_loan_change.emit(user, notional_with_fee, notional_with_fee,  0)
    return ()
end

####################################################################################
# @dev repay a partial amount of the loan
# @param input is 
# - the repayment amount in USDC that the user wants to repay
# this same function is called for a full repayment
####################################################################################
@external
func repay_loan_partial{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(repay : felt):
    alloc_locals
    # @dev addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, accrued_interest) = view_loan_detail(user)
    check_user_loan(notional)
    
    # @dev check repay doesnt exceed loan outstanding
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
    let (total_acrrued_notional_os) = calc_loan_outstanding(notional, accrued_interest, hist_accrual, hist_repay)
    check_repayment_amount(repay, total_acrrued_notional_os)

    # @dev test sufficient funds to repay
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    check_user_balance(usdc_addy, user, repay)  
    
    # @dev tranfers
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, repay)     
    # @dev new variable calcs
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (new_total_acrrued_notional_os) = Math10xx8_sub(total_acrrued_notional_os, repay)
    let (new_repayment) = Math10xx8_add(hist_repay, repay)
    let (new_reval_ts) = Math10xx8_ts()
    # @dev update CZCore - run accrual + update wt avg rate
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (residual_loan_capital) = calc_residual_loan_capital(notional, hist_repay, repay)
    CZCore.set_update_rate(czcore_addy, residual_loan_capital, rate, 0)
    let (new_loan_total) = Math10xx8_sub(loan_total, residual_loan_capital)

    if new_total_acrrued_notional_os == 0:
        # @dev if loan repaid in full, do accrual splits
        let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
        let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
        let (accrued_interest_lp, accrued_interest_if, accrued_interest_gt) = calc_accrued_interest_payments(total_accrual, lp_split, if_split, gt_split)
        CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, accrued_interest_if)
        # @dev update CZCore and loan  
        let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
        let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)
        CZCore.set_reduce_accrual(czcore_addy, total_accrual)
        CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, new_reward_total)

        # @dev transfer collateral back to user
        let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
        CZCore.erc20_transfer(czcore_addy, weth_addy, user, collateral)
        CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        # @dev emit event
        event_cb_loan_book.emit(user, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        event_cb_loan_change.emit(user, repay, new_total_acrrued_notional_os, 2)
        return ()
    else:
        CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
        CZCore.set_cb_loan(czcore_addy, user, notional, collateral, start_ts, new_reval_ts, end_ts, rate, total_accrual, new_repayment, liquidate_me, 0)
        # @dev emit event
        event_cb_loan_book.emit(user, notional, collateral, start_ts, new_reval_ts, end_ts, rate, total_accrual, new_repayment, liquidate_me)
        event_cb_loan_change.emit(user, repay, new_total_acrrued_notional_os, 1)
        return ()
    end
end

####################################################################################
# @dev repay the full amount of the loan
# this function calls the view_loan_detail function and then calls repay_loan_partial using the loan amount outstanding as input
# this is the current full loan amount and will close the loan
####################################################################################
@external
func repay_loan_full{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, accrued_interest) = view_loan_detail(user)
    let (total_acrrued_notional_os) = calc_loan_outstanding(notional, accrued_interest, hist_accrual, hist_repay)
    repay_loan_partial(total_acrrued_notional_os)
    return()
end

####################################################################################
# @dev this allows the user to increase their WETH collateral backing the loan
# @param input is the additional collateral to be added
# if user has 10 WETH backing loan and wants to increase this to 11 WETH, they pass 1 WETH in the function below
####################################################################################
@external
func increase_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(add_collateral : felt):
    alloc_locals
    # @dev Verify that the user has sufficient funds before call
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    check_user_balance(weth_addy, user, add_collateral)
    
    # @dev transfers
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, add_collateral)
    let (notional, old_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me) = CZCore.get_cb_loan(czcore_addy, user)
    let (new_collateral) = Math10xx8_add(old_collateral, add_collateral)
    CZCore.set_cb_loan(czcore_addy, user, notional, new_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, 0)
    # @dev emit event
    event_cb_loan_book.emit(user, notional, new_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me)  
    event_cb_loan_change.emit(user, add_collateral, 0, 3)
    return()
end

####################################################################################
# @dev this allows the user to decrease their WETH collateral backing the loan
# @param input is the collateral to be removed
# if user has 10 WETH backing loan and wants to decrease this to 9 WETH, they pass 1 WETH in the function below
####################################################################################
@external
func decrease_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(dec_collateral : felt):
    alloc_locals
    # @dev Verify amount positive
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (notional, old_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, accrued_interest) = view_loan_detail(user)
    check_collateral_withdraw(dec_collateral, old_collateral)

    # @dev check withdrawal would not make loan insolvent
    let (total_acrrued_notional_os) = calc_loan_outstanding(notional, accrued_interest, hist_accrual, hist_repay)
    let (new_collateral) = Math10xx8_sub(old_collateral, dec_collateral)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, total_acrrued_notional_os, new_collateral)

    # @dev transfer 
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    CZCore.set_cb_loan(czcore_addy, user, notional, new_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me, 0)
    CZCore.erc20_transfer(czcore_addy, weth_addy, user, dec_collateral)
    # @dev emit event
    event_cb_loan_book.emit(user, notional, new_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me)
    event_cb_loan_change.emit(user, dec_collateral, 0, 4)
    return()
end

####################################################################################
# @dev allow a user to refinance an existing loan 
# user can increase the notional, increase collateral, and/or change the end date
# cant use repay and then create loan since this requires the user to have the USDC to repay, which they might not have
# refinancing allows new loan creation/rolling without needing to close the old loan
# @param input is 
# - the additional notional needed in USDC (>= 0)
# - the additional collateral provided in WETH (>= 0)
# - the end date of the loan in timestamp
# see create loan above for more detail
####################################################################################
@external
func refinance_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(add_notional : felt, add_collateral : felt, end_ts : felt):
    alloc_locals
    # @dev addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (pp_addy) = TrustedAddy.get_pp_addy(_trusted_addy)
    let (old_notional, old_collateral, old_start_ts, old_reval_ts, old_end_ts, old_rate, hist_accrual, hist_repay, liquidate_me, accrued_interest) = view_loan_detail(user)
    check_user_loan(old_notional)
    
    # @dev check add_notional >= 0 and add_collateral >= 0
    check_notional_collateral(add_notional, add_collateral)

    # @dev calc repay amount as if closing loan
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
    let (repay) = calc_loan_outstanding(old_notional, accrued_interest, hist_accrual, hist_repay)

    # pay out accrued interest as per a full loan repayment
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
    let (df_addy) = TrustedAddy.get_df_addy(_trusted_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (accrued_interest_lp, accrued_interest_if, accrued_interest_gt) = calc_accrued_interest_payments(total_accrual, lp_split, if_split, gt_split)
    let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
    let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)

    # @dev process pp data
    let (rate) = PriceProvider.get_rate(pp_addy, end_ts)
    let (lp_yield_boost) = Settings.get_lp_yield_boost(settings_addy)
    let (rate_boost) = Math10xx8_add(rate, lp_yield_boost)
    
    # @dev data for checks
    let (notional) = Math10xx8_add(repay, add_notional) 
    let (collateral) = Math10xx8_add(old_collateral, add_collateral) 
    # @dev checks
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, notional, collateral)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    check_user_balance(weth_addy, user, add_collateral)
    check_utilization(settings_addy, add_notional, loan_total, capital_total)
    let (start_ts) = Math10xx8_ts()
    check_max_term(settings_addy, start_ts, end_ts)
    check_loan_range(settings_addy, notional)

    # @dev add origination fee
    let (fee, df_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (one) = Math10xx8_one()
    let (one_plus_fee) = Math10xx8_add(one, fee)
    let (notional_with_fee) = Math10xx8_mul(one_plus_fee, notional)
    let (origination_fee) = Math10xx8_sub(notional_with_fee, notional)

    # @dev calc amounts to transfer 
    let (df_fee) = Math10xx8_mul(origination_fee, df_split)
    let (if_fee) =  Math10xx8_mul(origination_fee, if_split)
    
    # @dev all transfers
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, add_collateral)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, add_notional)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, df_fee, df_fee)
    let (if_total) = Math10xx8_add(if_fee, accrued_interest_if)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, if_total)

    # @dev accrue to current ts and then updated wt avg rate
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (residual_loan_capital) = calc_residual_loan_capital(old_notional, hist_repay, repay)
    let (loan_total_dn) = Math10xx8_sub(loan_total, residual_loan_capital)
    let (new_loan_total) = Math10xx8_add(loan_total_dn, notional_with_fee)
    CZCore.set_update_rate(czcore_addy, residual_loan_capital, old_rate, 0)
    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, loan_total_dn, insolvency_total, new_reward_total)
    CZCore.set_update_rate(czcore_addy, notional_with_fee, rate_boost, 1)
    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, new_reward_total)
    CZCore.set_cb_loan(czcore_addy, user, notional_with_fee, collateral, start_ts, start_ts, end_ts, rate_boost, 0, 0, 0, 0)
    CZCore.set_reduce_accrual(czcore_addy, total_accrual)    
    # @dev emit event
    event_cb_loan_book.emit(user, notional_with_fee, collateral, start_ts, start_ts, end_ts, rate_boost, 0, 0, 0)
    event_cb_loan_change.emit(user, notional_with_fee, notional_with_fee, 5)
    return ()
end

####################################################################################
# @dev allow a user to flag their loan for liquidation
# in the case the user can not repay the USDC and wants to close the loan now
####################################################################################
@external
func flag_loan_liquidation{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    # @dev addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me) = CZCore.get_cb_loan(czcore_addy, user)
    check_user_loan(notional)
    
    # @dev update CZCore
    CZCore.set_cb_loan(czcore_addy, user, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, 1, 0)
    # @dev emit event
    event_cb_loan_book.emit(user, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, 1)
    return ()
end