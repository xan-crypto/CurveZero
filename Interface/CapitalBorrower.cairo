# CB contract
# all numbers passed into contract must be Math10xx8 type
# events include event_loan_change
# functions include repay_loan_full, repay_loan_partial, create_loan, refinance_loan, increase_collateral, decrease_collateral, view_loan_detail

# imports
%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_nn, assert_nn_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_pow_frac, Math10xx8_sub, Math10xx8_add, Math10xx8_ts, Math10xx8_one, Math10xx8_year, Math10xx8_convert_from
from Functions.Checks import check_is_owner, check_min_pp, check_ltv, check_utilization, check_max_term, check_loan_range, check_user_balance

##################################################################
# addy of the owner
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

##################################################################
# trusted addy where contract addys are stored, only owner can change this
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

##################################################################
# emit CB events to build/maintain the loan book for liquidation/monitoring/dashboard
@event
func event_loan_change(addy : felt, has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt):
end

##################################################################
# query a users loan
@view
func view_loan_detail{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
        has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, hist_accrual, accrued_interest : felt):
    alloc_locals
    # calc accrued interest and return loan details
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual) = CZCore.get_cb_loan(czcore_addy, user)
    let (block_ts) = Math10xx8_ts()
    let (one) = Math10xx8_one()
    let (year_secs) = Math10xx8_year()

    if has_loan == 0:
        return (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual, 0)
    else:
        let (test) = is_le(start_ts, block_ts)
        if test == 1:
            let (diff_ts) = Math10xx8_sub(block_ts, start_ts)
            let (year_frac) = Math10xx8_div(diff_ts, year_secs)
            let (one_plus_rate) = Math10xx8_add(one, rate)
            let (accrual) = Math10xx8_pow_frac(one_plus_rate, year_frac)
            let (accrued_notional) = Math10xx8_mul(notional, accrual)
            let (accrued_interest) = Math10xx8_sub(accrued_notional, notional)
            return (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual, accrued_interest)
        else:
            return (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual, 0)
        end
    end
end

# create new loan
@external
func create_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(loan_id : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt, pp_data : felt*):
    alloc_locals
    # addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (has_loan, a, b, c, d, e, f) = CZCore.get_cb_loan(czcore_addy, user)
    with_attr error_message("User already has an existing loan, refinance instead."):
        assert has_loan = 0
    end
    
    # process pp data
    let (median_rate, winning_pp, rate_array_len) = process_pp_data(loan_id, pp_data_len, pp_data)
    
    #checks
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

    # add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (one) = Math10xx8_one()
    let (one_plus_fee) = Math10xx8_add(one, fee)
    let (notional_with_fee) = Math10xx8_mul(one_plus_fee, notional)
    let (origination_fee) = Math10xx8_sub(notional_with_fee, notional)

    # calc amounts to transfer 
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (notional_erc) = Math10xx8_convert_from(notional, usdc_decimals)     
    let (pp_fee) = Math10xx8_mul(origination_fee, pp_split)
    let (pp_fee_erc) = Math10xx8_convert_from(pp_fee, usdc_decimals)
    let (if_fee) =  Math10xx8_mul(origination_fee, if_split)
    let (if_fee_erc) = Math10xx8_convert_from(if_fee, usdc_decimals)
    
    # all transfers
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, notional_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, winning_pp, pp_fee_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, if_fee_erc)
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)
    # update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, notional_with_fee, collateral, start_ts, end_ts, median_rate, 0, 1)
    let (new_loan_total) = Math10xx8_add(loan_total, notional_with_fee)
    CZCore.set_loan_total(czcore_addy, new_loan_total)
    #event
    event_loan_change.emit(addy=user, has_loan=1, notional=notional_with_fee, collateral=collateral, start_ts=start_ts, end_ts=end_ts, rate=median_rate, hist_accrual=0)
    return ()
end

# repay loan in partial
@external
func repay_loan_partial{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(repay : felt):
    alloc_locals
    # addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    with_attr error_message("User does not have an existing loan to repay."):
        assert has_loan = 1
    end
        
    # check repay doesnt exceed accrued notional
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    with_attr error_message("Repayment should be positive and at most the accrued notional."):
        assert_nn_le(repay, acrrued_notional)
    end

    # test sufficient funds to repay
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (repay_erc) = check_user_balance(user, usdc_addy, repay)  
    
    # tranfers
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, repay_erc)     
    # new variable calcs
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    with_attr error_message("Repay should be below loan total, overflow prevention."):
        assert_nn_le(repay, loan_total)
    end
    let (new_notional) = Math10xx8_sub(acrrued_notional, repay)
    let (new_start_ts) = Math10xx8_ts()
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)
    
    if new_notional == 0:
        # if loan repaid in full, do accrual splits
        let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
        let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
        let (accrued_interest_lp) = Math10xx8_mul(lp_split, total_accrual)
        let (accrued_interest_if) = Math10xx8_mul(if_split, total_accrual)
        let (accrued_interest_gt) = Math10xx8_mul(gt_split, total_accrual)
        let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
        let (accrued_interest_if_erc) = Math10xx8_convert_from(accrued_interest_if, usdc_decimals) 
        CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, accrued_interest_if_erc)
        # update CZCore and loan  
        let (loan_total_after_accrual) = Math10xx8_add(loan_total, total_accrual)
        let (new_loan_total) = Math10xx8_sub(loan_total_after_accrual, repay)
        let (new_capital_total) = Math10xx8_add(capital_total, accrued_interest_lp)
        let (new_reward_total) = Math10xx8_add(reward_total, accrued_interest_gt)
        CZCore.set_captal_loan_reward_total(czcore_addy, new_capital_total, new_loan_total, new_reward_total)
        CZCore.set_cb_loan(czcore_addy, user, 0, 0, collateral, 0, 0, 0, 0, 0)
        decrease_collateral(collateral)
        # event captured in decrease collateral
        return ()
    else:
        let (new_loan_total) = Math10xx8_sub(loan_total, repay)
        CZCore.set_loan_total(czcore_addy, new_loan_total)
        CZCore.set_cb_loan(czcore_addy, user, 1, new_notional, collateral, new_start_ts, end_ts, rate, total_accrual, 0)
        # event
        event_loan_change.emit(addy=user, has_loan=has_loan, notional=new_notional, collateral=collateral, start_ts=new_start_ts, end_ts=end_ts, rate=rate, hist_accrual=total_accrual)
        return ()
    end
end

# repay loan in full
@external
func repay_loan_full{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    repay_loan_partial(acrrued_notional)
    return()
end

# increase collateral
@external
func increase_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(collateral : felt):
    alloc_locals
    # Verify that the user has sufficient funds before call
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (collateral_erc) = check_user_balance(user, weth_addy, collateral)
    
    # transfers
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)
    let (has_loan, notional, old_collateral, start_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    let (new_collateral) = Math10xx8_add(collateral, old_collateral)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, new_collateral, start_ts, end_ts, rate, hist_accrual, 0)
    # event
    event_loan_change.emit(addy=user, has_loan=has_loan, notional=notional, collateral=new_collateral, start_ts=start_ts, end_ts=end_ts, rate=rate, hist_accrual=hist_accrual)  
    return()
end

# decrease collateral
@external
func decrease_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(collateral : felt):
    alloc_locals
    # Verify amount positive
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, old_collateral, start_ts, end_ts, rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    with_attr error_message("Collateral withdrawal should be positive and at most the user total collateral."):
       assert_nn_le(collateral, old_collateral)
    end
    
    # check withdrawal would not make loan insolvent
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    let (new_collateral) = Math10xx8_sub(old_collateral, collateral)
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, acrrued_notional, new_collateral)

    # test sufficient funds to repay
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (collateral_erc) = check_user_balance(czcore_addy, weth_addy, collateral)
        
    # transfer 
    CZCore.erc20_transfer(czcore_addy, weth_addy, user, collateral_erc)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, new_collateral, start_ts, end_ts, rate, hist_accrual, 0)
    # event
    event_loan_change.emit(addy=user, has_loan=has_loan, notional=notional, collateral=new_collateral, start_ts=start_ts, end_ts=end_ts, rate=rate, hist_accrual=hist_accrual)
    return()
end

# refinance laon
@external
func refinance_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(loan_id : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt,pp_data : felt*):
    alloc_locals
    # addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (has_loan, old_notional, old_collateral, old_start_ts, old_end_ts, old_rate, hist_accrual, accrued_interest) = view_loan_detail(user)
    with_attr error_message("User does not have an existing loan."):
        assert has_loan = 1
    end
    
    # check notional great than old notional + accured interest
    let (accrued_old_notional) = Math10xx8_add(old_notional, accrued_interest) 
    with_attr error_message("New notional should be greater than accrued old notional."):
        assert_nn_le(accrued_old_notional, notional)
    end
    with_attr error_message("New collateral should be greater than or equal to old collateral."):
        assert_nn_le(old_collateral, collateral)
    end
    
    # process pp data
    let (median_rate, winning_pp, rate_array_len) = process_pp_data(loan_id, pp_data_len, pp_data)
    
    #checks
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

    # add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (one) = Math10xx8_one()
    let (one_plus_fee) = Math10xx8_add(one, fee)
    let (change_notional_with_fee) = Math10xx8_mul(one_plus_fee, change_notional)
    let (origination_fee) = Math10xx8_sub(change_notional_with_fee, change_notional)

    # calc amounts to transfer 
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (change_notional_erc) = Math10xx8_convert_from(change_notional, usdc_decimals)    
    let (pp_fee) = Math10xx8_mul(origination_fee, pp_split)
    let (pp_fee_erc) = Math10xx8_convert_from(pp_fee, usdc_decimals)
    let (if_fee) =  Math10xx8_mul(origination_fee, if_split)
    let (if_fee_erc) = Math10xx8_convert_from(if_fee, usdc_decimals)
    let (new_notional_with_fee) = Math10xx8_add(accrued_old_notional, change_notional_with_fee)
    let (total_accrual) = Math10xx8_add(hist_accrual, accrued_interest)

    # all transfers
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, change_notional_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, winning_pp, pp_fee_erc)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, if_addy, if_fee_erc)
    if change_collateral != 0:
        CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, change_collateral_erc)
    end
    # update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, new_notional_with_fee, collateral, start_ts, end_ts, median_rate, total_accrual, 0)
    let (new_loan_total) = Math10xx8_add(loan_total, change_notional_with_fee)
    CZCore.set_loan_total(czcore_addy, new_loan_total)
    #event
    event_loan_change.emit(addy=user, has_loan=has_loan, notional=new_notional_with_fee, collateral=collateral, start_ts=start_ts, end_ts=end_ts, rate=median_rate, hist_accrual=total_accrual)
    return ()
end

##################################################################
# process pp data
func process_pp_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*}(loan_id : felt, pp_data_len: felt, pp_data : felt*) -> (median_rate: felt, winning_pp : felt, rate_array_len : felt):
    alloc_locals
    # pp data should be passed as follows
    # [ signed_loanID_r , signed_loanID_s , signed_rate_r , signed_rate_s , rate , pp_pub , ..... ]
    let (loan_id_hash) = hash2{hash_ptr=pedersen_ptr}(loan_id, 0)
    let (rate_array : felt*) = alloc()
    let (pp_pub_array : felt*) = alloc()
    # iterate thru pp_pub and reduce total dataset where pp_pub is not valid PP
    # re enable this later
    # let (new_pp_data_len, new_pp_data) = validate_pp_data(pp_data_len,pp_data)
    # iterate thru remaining pp data - verify the pp's signature for both rate and unique loan ID.
    # let (rate_array_len, rate_array, pp_pub_array_len, pp_pub_array) = check_pricing(new_pp_data_len, new_pp_data, loan_id_hash)
    let (rate_array_len, rate_array, pp_pub_array_len, pp_pub_array) = check_pricing(pp_data_len, pp_data, loan_id_hash)
    # order the rates and find the median
    let (len_ordered, ordered, len_index, index) = sort_index(rate_array_len, rate_array, rate_array_len, rate_array)
    let (median, _) = unsigned_div_rem(len_ordered, 2)
    # later randomly select 75% of the PPs, also deal with median when even number of PP
    let median_rate = ordered[median]    
    let winning_position = index[median]
    let winning_pp = pp_pub_array[winning_position]
    return(median_rate, winning_pp, rate_array_len)
end

# iterate thru pp_pub and reduce total dataset where pp_pub is not valid PP
func validate_pp_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(length: felt, array : felt*) -> (pp_data_len: felt, pp_data : felt*):
    alloc_locals
    if length == 0:
        let (pp_data : felt*) = alloc()
        return (0, pp_data)
    end
    # recursive call
    let (pp_data_len, pp_data) = validate_pp_data(length - 6, array + 6)
    # validate PP status
    let pp_pub = array[5]
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_token, czt_token, status) = CZCore.get_pp_status(czcore_addy, pp_pub)
    # add to new arrays
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

# check all PPs data correctly signed - check sigs vs. signed loan and sigs vs. signed rate provided
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

# this function returns to min value of an array and the index thereof
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

# this function sorts an array of size n from high to low - need this for the median calc for PPs
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
