####################################################################################
# @title CapitalBorrower contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - create a USDC loan in return for WETH collateral
# - view their current loan if any including the current accrued interest to date
# - increase their collateral for the loan
# - decrease their collateral for the loan subject to LTV setting within the Settings contract
# - make a partial repayment of the loan
# - make a full repayment of the loan
# - refinance or roll the loan, i.e. increase the notional needed and/or change the end date
# There are various internal functions at the end of this contract that aid with PP data processing
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_nn, assert_nn_le
from starkware.cairo.common.math_cmp import is_le, is_nn
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add, Math10xx8_ts, Math10xx8_one, Math10xx8_year, Math10xx8_convert_from, Math10xx8_zero
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
# @dev emit CB events to build/maintain the loan book for liquidation/monitoring/dashboard
####################################################################################
@event
func event_loan_change(addy : felt, has_loan : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts: felt, end_ts : felt, rate : felt, hist_accrual : felt):
end

####################################################################################
# @dev query a users loan details
# we added some protect to the accrued interest calcuation, the math lib is an approximation
# this means for very small ts diff and compound interest, the accrual can be negative which could be an attack vector
# to fix this we just check that the accrual is positive else we set to 0
# going forward we are switching to curve build using compound interest, PP will quote simple interest equivalent tho
# see google sheet for approach here: https://docs.google.com/spreadsheets/d/1QcHmy5CtCYYY8k9GpJEu59zyqS9kXyzbcR3Lkv4QXJo/edit?usp=sharing
# main issue with using compound interest for everything is that we could not efficiently value the entire loan book cheaply
# meaning that LP accrual happened at time of cash flow vs continuously, the latter being preferred
# @param input is 
# - the addy of the user in question
# @return 
# - whether the user has a loan or not has_loan = 0 - false has_loan = 1 - true
# - the notional of the loan in USDC, including any origination fees at initiation  
# - the collateral in WETH that backs this loan
# - the start date in timestamp when the loan was taken (partial repay does not affect this date, refinancing does tho) - used for UX
# - the revaluation date (either the loan start date or the last repayment or the last refinancing)
# - the end date in timestamp
# - the median rate the loan was set at, given the pricing obtained by pricing providers (quoted and stored as simple interest)
# - the historical accrual which is needed for cashflow vs loan recon, if a loan is changed, this records the historical accrual
# so that the correct fees can be paid to the LP/IF/GT when the loan is closed out
# - the accrued interest is the simple interest on the loan notional from reval date to current time
####################################################################################
@view
func view_loan_detail{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
        has_loan : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual, accrued_interest : felt):
    alloc_locals
    # @dev calc accrued interest and return loan details
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual) = CZCore.get_cb_loan(czcore_addy, user)
    let (block_ts) = Math10xx8_ts()
    let (one) = Math10xx8_one()
    let (year_secs) = Math10xx8_year()

    if has_loan == 0:
        return (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, 0)
    else:
        let (diff_ts) = Math10xx8_sub(block_ts, reval_ts)
        let (year_frac) = Math10xx8_div(diff_ts, year_secs)
        let (rate_year_frac) = Math10xx8_mul(rate, year_frac)
        let (accrual) = Math10xx8_add(one, rate_year_frac)
        let (accrued_notional) = Math10xx8_mul(notional, accrual)
        let (accrued_interest) = Math10xx8_sub(accrued_notional, notional)
        let (test_accrued_interest) = is_nn(accrued_interest)
        if test_accrued_interest == 1:
            return (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, accrued_interest)
        else:
            return (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, 0)
        end
    end
end

####################################################################################
# @dev create a new loan for a user
# @param input is 
# - the unique loan id for this particular loan as created by the frontend, and passed to the PPs for signing
# - the notional of the loan in USDC
# - the collateral of the loan in WETH
# - the end date of the loan in timestamp
# - the number of data points in the PP pricing dataset, each PP returns 6 felts, so if there is 5 PPs in total, expect 30 datapoints
# system will function with any number of PPs as long as the number of PPs is above or equal to the min required in the Settings contract
# - the pp dataset takes the following format
# [ signed_hash_loanID_r , signed_hash_loanID_s , signed_hash_rate_r , signed_hash_rate_s , rate , pp_pub , ..... ]
# the signed unique loan ID prevents a replay attack where someone submits historic pricing on the PPs behalf
# we validate that the pp_pub matches the set of all valid PPs per the PriceProvider contract, any others are kicked out
# we validate that the PP signed both the unique loan ID and the rate
# if any of the signatures dont match or if the total valid PPs are below min, the loan creation will fail
# there is some risk that the front end will not pass all the PP data, hence the min PP requirement
# median pricing of a sufficiently large batch will yield a reasonable result
####################################################################################
@external
func create_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(loan_id : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt, pp_data : felt*):
    alloc_locals
    # @dev addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (has_loan, a, b, c, d, e, f, g) = CZCore.get_cb_loan(czcore_addy, user)
    with_attr error_message("User already has an existing loan, refinance loan instead."):
        assert has_loan = 0
    end
    
    # @dev process pp data 
    # lp yield boost is set by governance and is effectively a parallel shift of the curve upward to balance supply demand / attract lp capital
    let (median_rate, winning_pp, rate_array_len) = process_pp_data(loan_id, pp_data_len, pp_data)
    let (lp_yield_boost) = Settings.get_lp_yield_boost(settings_addy)
    let (median_rate_boost) = Math10xx8_add(median_rate, lp_yield_boost)
    
    # @dev checks
    check_min_pp(settings_addy, rate_array_len)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, notional, collateral)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (collateral_erc) = check_user_balance(user, weth_addy, collateral)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_utilization(settings_addy, notional, loan_total, capital_total)
    let (start_ts) = Math10xx8_ts()
    check_max_term(settings_addy, start_ts, end_ts)
    check_loan_range(settings_addy, notional)

    # @dev add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (one) = Math10xx8_one()
    let (one_plus_fee) = Math10xx8_add(one, fee)
    let (notional_with_fee) = Math10xx8_mul(one_plus_fee, notional)
    let (origination_fee) = Math10xx8_sub(notional_with_fee, notional)

    # @dev calc amounts to transfer 
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (notional_erc) = Math10xx8_convert_from(notional, usdc_decimals)     
    let (pp_fee) = Math10xx8_mul(origination_fee, pp_split)
    let (pp_fee_erc) = Math10xx8_convert_from(pp_fee, usdc_decimals)
    let (if_fee) =  Math10xx8_mul(origination_fee, if_split)
    let (if_fee_erc) = Math10xx8_convert_from(if_fee, usdc_decimals)
    
    # @dev all transfers
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, notional_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, winning_pp, pp_fee_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, if_fee_erc)
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)
    # @dev update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, notional_with_fee, collateral, start_ts, start_ts, end_ts, median_rate_boost, 0, 1)
    let (new_loan_total) = Math10xx8_add(loan_total, notional_with_fee)
    CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
    # @dev emit event
    event_loan_change.emit(addy=user, has_loan=1, notional=notional_with_fee, collateral=collateral, start_ts=start_ts, reval_ts=start_ts, end_ts=end_ts, rate=median_rate_boost, hist_accrual=0)
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
    let (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    with_attr error_message("User does not have an existing loan to repay."):
        assert has_loan = 1
    end
        
    # @dev check repay doesnt exceed accrued notional
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    with_attr error_message("Partial repayment should be positive and at most the accrued notional, consider using repay full."):
        assert_nn_le(repay, acrrued_notional)
    end

    # @dev test sufficient funds to repay
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (repay_erc) = check_user_balance(user, usdc_addy, repay)  
    
    # @dev tranfers
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, repay_erc)     
    # @dev new variable calcs
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (new_notional) = Math10xx8_sub(acrrued_notional, repay)
    let (new_reval_ts) = Math10xx8_ts()
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
    
    if new_notional == 0:
        # @dev if loan repaid in full, do accrual splits
        let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
        let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
        let (accrued_interest_lp) = Math10xx8_mul(lp_split, total_accrual)
        let (accrued_interest_if) = Math10xx8_mul(if_split, total_accrual)
        let (accrued_interest_gt) = Math10xx8_mul(gt_split, total_accrual)
        let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
        let (accrued_interest_if_erc) = Math10xx8_convert_from(accrued_interest_if, usdc_decimals) 
        CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, accrued_interest_if_erc)
        # @dev update CZCore and loan  
        let (loan_total_after_accrual) = Math10xx8_add(loan_total, total_accrual)
        let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
        let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)
        # @dev in the rare case of indirect rounding issues
        let (test) = is_le(repay, loan_total_after_accrual)
        if test == 1:
            let (new_loan_total) = Math10xx8_sub(loan_total_after_accrual, repay)
            CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, new_reward_total)
        else:
            let (new_loan_total) = Math10xx8_zero()
            CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, new_loan_total, insolvency_total, new_reward_total)
        end
        CZCore.set_cb_loan(czcore_addy, user, 0, 0, collateral, 0, 0, 0, 0, 0, 0)
        decrease_collateral(collateral)
        # @dev event captured in decrease collateral
        return ()
    else:
        let (new_loan_total) = Math10xx8_sub(loan_total, repay)
        CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
        CZCore.set_cb_loan(czcore_addy, user, 1, new_notional, collateral, start_ts, new_reval_ts, end_ts, rate, total_accrual, 0)
        # @dev emit event
        event_loan_change.emit(addy=user, has_loan=has_loan, notional=new_notional, collateral=collateral, start_ts=start_ts, reval_ts=new_reval_ts, end_ts=end_ts, rate=rate, hist_accrual=total_accrual)
        return ()
    end
end

####################################################################################
# @dev repay the full amount of the loan
# this function calls the view_loan_detail function and then calls repay_loan_partial using the notional + accrued interest as input
# this is the current full loan amount and will close the loan
####################################################################################
@external
func repay_loan_full{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    repay_loan_partial(acrrued_notional)
    return()
end

####################################################################################
# @dev this allows the user to increase their WETH collateral backing the loan
# @param input is the additional collateral to be added
# if user has 10 WETH backing loan and wants to increase this to 11 WETH, they pass 1 WETH in the function below
####################################################################################
@external
func increase_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(collateral : felt):
    alloc_locals
    # @dev Verify that the user has sufficient funds before call
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (collateral_erc) = check_user_balance(user, weth_addy, collateral)
    
    # @dev transfers
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)
    let (has_loan, notional, old_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    let (new_collateral) = Math10xx8_add(collateral, old_collateral)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, new_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, 0)
    # @dev emit event
    event_loan_change.emit(addy=user, has_loan=has_loan, notional=notional, collateral=new_collateral, start_ts=start_ts, reval_ts=reval_ts, end_ts=end_ts, rate=rate, hist_accrual=hist_accrual)  
    return()
end

####################################################################################
# @dev this allows the user to decrease their WETH collateral backing the loan
# @param input is the collateral to be removed
# if user has 10 WETH backing loan and wants to decrease this to 9 WETH, they pass 1 WETH in the function below
####################################################################################
@external
func decrease_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(collateral : felt):
    alloc_locals
    # @dev Verify amount positive
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, old_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    with_attr error_message("Collateral withdrawal should be positive and at most the user total collateral."):
       assert_nn_le(collateral, old_collateral)
    end
    
    # @dev check withdrawal would not make loan insolvent
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    let (new_collateral) = Math10xx8_sub(old_collateral, collateral)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, acrrued_notional, new_collateral)

    # @dev test sufficient funds to repay
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (collateral_erc) = check_user_balance(czcore_addy, weth_addy, collateral)
        
    # @dev transfer 
    CZCore.erc20_transfer(czcore_addy, weth_addy, user, collateral_erc)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, new_collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, 0)
    # @dev emit event
    event_loan_change.emit(addy=user, has_loan=has_loan, notional=notional, collateral=new_collateral, start_ts=start_ts, reval_ts=reval_ts, end_ts=end_ts, rate=rate, hist_accrual=hist_accrual)
    return()
end

####################################################################################
# @dev allow a user to refinance an existing loan 
# user can increase the notional, increase collateral, change the end date, this requires new PP pricing data
# cant use repay and then create loan since this requires the user to have the USDC to repay, which they might not have
# refinancing allows new loan creation/rolling without needing to close the old loan
# @param input is 
# - the unique loan id for this particular loan as created by the frontend, and passed to the PPs for signing
# - the new notional of the loan in USDC (must be greater than notional + accrued interest)
# - the new collateral of the loan in WETH (must be the same or greater than current, can use decrease collateral post if needed)
# - the end date of the loan in timestamp
# - the number of data points in the PP pricing dataset
# - the pp dataset which takes the following format
# [ signed_hash_loanID_r , signed_hash_loanID_s , signed_hash_rate_r , signed_hash_rate_s , rate , pp_pub , ..... ]
# see create loan above for more detail
####################################################################################
@external
func refinance_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(loan_id : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt,pp_data : felt*):
    alloc_locals
    # @dev addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (has_loan, old_notional, old_collateral, old_start_ts, old_reval_ts, old_end_ts, old_rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    with_attr error_message("User does not have an existing loan to refinance."):
        assert has_loan = 1
    end
    
    # @dev check notional great than old notional + accured interest
    let (accrued_old_notional) = Math10xx8_add(old_notional, accrued_interest) 
    with_attr error_message("New notional should be greater than accrued old notional."):
        assert_nn_le(accrued_old_notional, notional)
    end
    with_attr error_message("New collateral should be greater than or equal to old collateral."):
        assert_nn_le(old_collateral, collateral)
    end
    
    # @dev process pp data
    let (median_rate, winning_pp, rate_array_len) = process_pp_data(loan_id, pp_data_len, pp_data)
    let (lp_yield_boost) = Settings.get_lp_yield_boost(settings_addy)
    let (median_rate_boost) = Math10xx8_add(median_rate, lp_yield_boost)
    
    # @dev checks
    check_min_pp(settings_addy, rate_array_len)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, notional, collateral)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (change_notional) = Math10xx8_sub(notional, accrued_old_notional) 
    let (change_collateral) = Math10xx8_sub(collateral, old_collateral) 
    let (change_collateral_erc) = check_user_balance(user, weth_addy, change_collateral)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_utilization(settings_addy, change_notional, loan_total, capital_total)
    let (start_ts) = Math10xx8_ts()
    check_max_term(settings_addy, start_ts, end_ts)
    check_loan_range(settings_addy, notional)

    # @dev add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (one) = Math10xx8_one()
    let (one_plus_fee) = Math10xx8_add(one, fee)
    let (change_notional_with_fee) = Math10xx8_mul(one_plus_fee, change_notional)
    let (origination_fee) = Math10xx8_sub(change_notional_with_fee, change_notional)

    # @dev calc amounts to transfer 
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (change_notional_erc) = Math10xx8_convert_from(change_notional, usdc_decimals)    
    let (pp_fee) = Math10xx8_mul(origination_fee, pp_split)
    let (pp_fee_erc) = Math10xx8_convert_from(pp_fee, usdc_decimals)
    let (if_fee) =  Math10xx8_mul(origination_fee, if_split)
    let (if_fee_erc) = Math10xx8_convert_from(if_fee, usdc_decimals)
    let (new_notional_with_fee) = Math10xx8_add(accrued_old_notional, change_notional_with_fee)
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)

    # @dev all transfers
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, change_notional_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, winning_pp, pp_fee_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, if_fee_erc)
    if change_collateral != 0:
        CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, change_collateral_erc)
    end
    # @dev update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, new_notional_with_fee, collateral, start_ts, start_ts, end_ts, median_rate_boost, total_accrual, 0)
    let (new_loan_total) = Math10xx8_add(loan_total, change_notional_with_fee)
    CZCore.set_cz_state(czcore_addy, lp_total, capital_total, new_loan_total, insolvency_total, reward_total)
    # @dev emit event
    event_loan_change.emit(addy=user, has_loan=has_loan, notional=new_notional_with_fee, collateral=collateral, start_ts=start_ts, reval_ts=start_ts, end_ts=end_ts, rate=median_rate_boost, hist_accrual=total_accrual)
    return ()
end

####################################################################################
# @dev process pp data
# this is an internal function
# it iterates thru pp_data and checks if pp_pub is a valid PP per CZCore, it removes those that are not valid
# then it checks that all signatures of remaining PPs are valid
# lastly calculates the median rate and winning pp_pub that will receive the origination fee
# @param input is 
# - the unhashed unique loan id
# - the pp data len for array manipulation
# - the total pp data set (num pp submissions x 6 data points expected)
# @return
# - the median rate for the loan (this is similar to chainlink oracles, get x prices and take median as result)
# this ensures that even if 4/9 PPs are malicious, the loan will still price correcly since median would be sensible
# this is worse case since it assume all malicious inputs are in the same direction
# - the pp_pub of the winning PP (the one that was the median) - needed in order to pay the origination fee
# - rate array len which is used to check that there was sufficient valid PPs above the required min
####################################################################################
func process_pp_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(loan_id : felt, pp_data_len: felt, pp_data : felt*) -> (median_rate: felt, winning_pp : felt, rate_array_len : felt):
    alloc_locals
    # @dev pp data should be passed as follows
    # [ signed_loanID_r , signed_loanID_s , signed_rate_r , signed_rate_s , rate , pp_pub , ..... ]
    let (loan_id_hash) = hash2{hash_ptr=pedersen_ptr}(loan_id, 0)
    let (rate_array : felt*) = alloc()
    let (pp_pub_array : felt*) = alloc()
    # @dev iterate thru pp_pub and reduce total dataset where pp_pub is not valid PP
    # re enable this later
    # let (new_pp_data_len, new_pp_data) = validate_pp_data(pp_data_len,pp_data)
    # @dev iterate thru remaining pp data - verify the pp's signature for both rate and unique loan ID.
    # let (rate_array_len, rate_array, pp_pub_array_len, pp_pub_array) = check_pricing(new_pp_data_len, new_pp_data, loan_id_hash)
    let (rate_array_len, rate_array, pp_pub_array_len, pp_pub_array) = check_pricing(pp_data_len, pp_data, loan_id_hash)
    # @dev order the rates and find the median
    let (len_ordered, ordered, len_index, index) = sort_index(rate_array_len, rate_array, rate_array_len, rate_array)
    let (median, _) = unsigned_div_rem(len_ordered, 2)
    # @dev later randomly select 75% of the PPs, also deal with median when even number of PP
    let median_rate = ordered[median]    
    let winning_position = index[median]
    let winning_pp = pp_pub_array[winning_position]
    with_attr error_message("Median rate must be greater than or equal to zero."):
        assert_nn(median_rate)
    end
    return(median_rate, winning_pp, rate_array_len)
end

####################################################################################
# @dev this function checks if pp_pub is valid vs CZCore
# this is an internal function
# @param input is 
# - the len of the pp data for array manipulation
# - the actual raw pp data
# @return
# - a reduced length of valid pp_pubs
# - a reduced dataset of valid pp submissions 
####################################################################################
func validate_pp_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(length: felt, array : felt*) -> (pp_data_len: felt, pp_data : felt*):
    alloc_locals
    if length == 0:
        let (pp_data : felt*) = alloc()
        return (0, pp_data)
    end
    # @dev recursive call
    let (pp_data_len, pp_data) = validate_pp_data(length - 6, array + 6)
    # @dev validate PP status
    let pp_pub = array[5]
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_token, czt_token, status) = CZCore.get_pp_status(czcore_addy, pp_pub)
    # @dev add to new arrays
    if status == 1:
        assert [pp_data + 0 + pp_data_len] = array[0]
        assert [pp_data + 1 + pp_data_len] = array[1]
        assert [pp_data + 2 + pp_data_len] = array[2]
        assert [pp_data + 3 + pp_data_len] = array[3]
        assert [pp_data + 4 + pp_data_len] = array[4]
        assert [pp_data + 5 + pp_data_len] = array[5]
        return (pp_data_len+6,pp_data)
    else:
        return (pp_data_len,pp_data)
    end
end

####################################################################################
# @dev check remaining PPs data correctly signed - check sigs vs. signed loan and sigs vs. signed rate provided
# then break these into 2 arrays, 1 for the rates and 1 for the pp_pubs
# this is an internal function
# @param input is 
# - length of pp data array
# - array of PP data
# - hash loan ID
# @return
# - length of rate array
# - rate array
# - length of pp_pub array
# - pp_pub array
####################################################################################
func check_pricing{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(length : felt, array : felt*, loan_hash : felt) -> (r_array_len : felt, r_array : felt*, p_array_len : felt, p_array : felt*):
    alloc_locals
    # create arrays at last step
    if length == 0:
        let (r_array : felt*) = alloc()
        let (p_array : felt*) = alloc()
        return (0, r_array, 0, p_array)
    end
    # recursive call
    let (r_array_len, r_array, p_array_len, p_array) = check_pricing(length - 6, array + 6, loan_hash)
    # validate that the PP signed both loanID and rate correctly
    let signed_loan_r = array[0]
    let signed_loan_s = array[1]
    let signed_rate_r = array[2]
    let signed_rate_s = array[3]
    let rate = array[4]
    let pp_pub = array[5]
    let (rate_hash) = hash2{hash_ptr=pedersen_ptr}(rate, 0)
    verify_ecdsa_signature(message=loan_hash, public_key=pp_pub, signature_r=signed_loan_r, signature_s=signed_loan_s)    
    verify_ecdsa_signature(message=rate_hash, public_key=pp_pub, signature_r=signed_rate_r, signature_s=signed_rate_s)
    # add to new arrays
    assert [r_array + r_array_len] = rate
    assert [p_array + p_array_len] = pp_pub
    return (r_array_len + 1, r_array, p_array_len + 1, p_array)
end

####################################################################################
# @dev this function returns the min value of an array and the index thereof
# this is needed for sorting as there is no native sorting function in cairo
# this is an internal function
# @param input is 
# - a hurdle level, look for the min value above this
# - array length
# - array
# @return
# - the min value above the hurdle
# - the index of this value in the array
####################################################################################
func get_min_value_above{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(x : felt, array_len : felt, array : felt*) -> (y : felt, index : felt):
    alloc_locals
    if array_len == 1:
        return (array[0], 0)
    end
    let (y, index) = get_min_value_above(x, array_len - 1, array + 1)
    let (test1) = is_le(array[0], y)
    if test1 == 1:
        let (test2) = is_le(array[0], x)
        if test2 == 0:
            let y = array[0]
            let index = 0
            return (y, index)
        else:
            let index = index + 1
            return (y, index)
        end
    else:
        let index = index + 1
        return (y, index)
    end
end

####################################################################################
# @dev this function sorts an array of size n from high to low - need this for the median calc for PPs
# this is needed for sorting as there is no native sorting function in cairo
# this is an internal function
# @param input is 
# - array length
# - array
# - array length (same array passed, need original + reduced one for recursion)
# - array (same array passed, need original + reduced one for recursion)
# @return
# - rate array length
# - rate array
# - index array length
# - index array
####################################################################################
func sort_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(x_len : felt, x : felt*, y_len : felt, y : felt*) -> (z_len : felt, z : felt*, i_len : felt, i : felt*):
    alloc_locals
    if y_len == 1:
        let (z : felt*) = alloc()
        let (i : felt*) = alloc()
        let (min, index) = get_min_value_above(0, x_len, x)
        assert [z] = min
        assert [i] = index
        return (1, z, 1, i)
    end
    let (z_len, z, i_len, i) = sort_index(x_len, x, y_len - 1, y + 1)
    let (min, index) = get_min_value_above(z[z_len - 1], x_len, x)
    assert [z + z_len] = min
    assert [i + i_len] = index
    return (z_len + 1, z, i_len + 1, i)
end
