# CB contract
# all numbers passed into contract must be Math64x61 type
# events include event_loan_change
# functions include repay_loan_full, repay_loan_partial, create_loan, refinance_loan, increase_collateral, decrease_collateral, view_loan_detail

# imports
%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_nn
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import unsigned_div_rem, assert_in_range
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20, Oracle
from Functions.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_pow_frac, Math64x61_sub, Math64x61_add, Math64x61_ts, Math64x61_one, Math64x61_year
from Functions.Checks import check_is_owner

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
func event_loan_change.emit(addy : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt)
end

##################################################################
# query a users loan
@view
func view_loan_detail{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
        has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, accrued_interest : felt):
    
    alloc_locals
    # calc accrued interest and return loan details
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate) = CZCore.get_cb_loan(czcore_addy, user)
    let (block_ts) = Math64x61_ts()
    let (one) = Math64x61_one()
    let (year_secs) = Math64x61_year()

    if has_loan == 0:
        return (has_loan, notional, collateral, start_ts, end_ts, rate, 0)
    else:
        let (diff_ts) = Math64x61_sub(block_ts, start_ts)
        let (year_frac) = Math64x61_div(diff_ts, year_secs)
        let (one_plus_rate) = Math64x61_add(one, rate)
        let (accrual) = Math64x61_pow_frac(one_plus_rate, year_frac)
        let (accrued_notional) = Math64x61_mul(notional, accrual)
        let (accrued_interest) = Math64x61_sub(accrued_notional, notional)
        return (has_loan, notional, collateral, start_ts, end_ts, rate, accrued_interest)
    end
end

# create new loan
@external
func create_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}
        (loan_id : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt, pp_data : felt*) - > (res : felt):
    
    # addys and check if existing loan
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, a, b, c, d, e) = CZCore.get_cb_loan(czcore_addy, user)
    with_attr error_message("User already has an existing loan, refinance instead."):
        assert has_loan = 0
    end
    
    # pp data should be passed as follows
    # [ signed_loanID_r , signed_loanID_s , signed_rate_r , signed_rate_s , rate , pp_pub , ..... ]
    let (loan_id_hash) = hash2{hash_ptr=pedersen_ptr}(loan_id, 0)
    let (rate_array : felt*) = alloc()
    let (pp_pub_array : felt*) = alloc()
    # iterate thru pp data - verify the pp's signature.
    let (rate_array_len, rate_array, pp_pub_array_len, pp_pub_array) = check_pricing(pp_data_len, pp_data, loan_id_hash)
    # check eno pp for pricing, settings has min_pp
    let (setting_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    check_min_pp(setting_addy, rate_array_len)
    # order the rates and find the median
    let (len_ordered, ordered, len_index, index) = sort_index(rate_array_len, rate_array, rate_array_len, rate_array)
    let (median, _) = unsigned_div_rem(len_ordered, 2)
    # later randomly select 75% of the PPs, also deal with median when even number of PP
    let (median_rate) = ordered[median]    
    let (winning_position) = index[median]
    let (winning_pp) = pp_pub_array[winning_position]

    # test sufficient collateral to proceed vs notional of loan
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    check_ltv(oracle_addy, settings_addy, notional, collateral)
    
    # Verify that the user has sufficient funds before call
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    
    let (weth_user) = Erc20.ERC20_balanceOf(weth_addy, user)   
    let (weth_quant_decimals) = Erc20.ERC20_decimals(weth_addy)   
    let (collateral_erc) = Math64x61_convert_from(collateral,weth_quant_decimals) 
    with_attr error_message("User does not have sufficient funds."):
       assert_le(collateral_erc, weth_user)
    enn
    
    # check below utilization level post loan
    let (lp_total,capital_total,loan_total,insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (stop) = Settings.get_utilization(settings_addy)
    let (temp4) = Math64x61_add(notional,loan_total)
    let (temp5) = Math64x61_div(temp4,capital_total)
    with_attr error_message("Utilization to high, cannot issue loan."):
       assert_le(temp5, stop)
    enn
    
    # check end time less than setting max loan time
    let (block_ts) = Math64x61_ts()
    let (max_term) = Settings.get_max_loan_term(settings_addy)
    let (temp6) = Math64x61_add(block_ts,max_term)
    with_attr error_message("Loan term should be within term range."):
       assert_in_range(end_ts, block_ts, temp6)
    enn

    # check loan amount within correct ranges
    let (min_loan,max_loan) = Settings.get_min_max_loan(settings_addy)
    with_attr error_message("Notional should be within min max loan range."):
       assert_in_range(notional, min_loan, max_loan)
    enn

    # add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (temp7) = Math64x61_add(fee,Math64x61_ONE)
    let (notional_with_fee) = Math64x61_mul(temp7,notional)

    # transfer collateral to CZCore and transfer USDC to user
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (notional_erc) = Math64x61_convert_from(notional,usdc_decimals) 
    let (origination_fee) = Math64x61_sub(notional_with_fee,notional)
    let (temp8) = Math64x61_mul(origination_fee,pp_split)
    let(fee_erc_pp) = Math64x61_convert_from(temp8,usdc_decimals)
    let (temp9) =  Math64x61_mul(origination_fee,if_split)
    let (fee_erc_if) = Math64x61_convert_from(temp9,usdc_decimals)
    let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)

    # transfer the actual USDC tokens to user - ERC decimal version
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, user, notional_erc)
    # transfer pp and if
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, winning_pp, fee_erc_pp)
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, if_addy, fee_erc_if)
    # transfer the actual WETH tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)
    #update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, notional_with_fee, collateral, block_ts, end_ts, median_rate, 0)
    let (lp_total, capital_total, loan_total, insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (new_loan_total) = Math64x61_add(loan_total,notional_with_fee)
    CZCore.set_loan_total(czcore_addy, new_loan_total)
    
    #event
    loan_change.emit(addy=user, notional=notional_with_fee, collateral=collateral,start_ts=block_ts,end_ts=end_ts,rate=median_rate)
    return (1)
end

# repay loan in partial
@external
func repay_loan_partial{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(repay : felt) - > (res : felt):
    
    # addys and check if existing loan
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate, accrued_interest) = get_loan_details(user)
    with_attr error_message("User does not have an existing loan to repay."):
        assert has_loan = 1
    end
        
    # new notional = old notional + ai -repay
    let (acrrued_notional) = Math64x61_add(notional,accrued_interest)
    let (block_ts) = Math64x61_ts()

    # check that repay positive and le accrued notional
    with_attr error_message("Repayment amount should be positive and at most the accrued notional."):
        assert assert_nn_le(repay,acrrued_notional)
    end

    # test sufficient funds to repay
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_user) = Erc20.ERC20_balanceOf(usdc_addy, user)   
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)   
    let (weth_decimals) = Erc20.ERC20_decimals(weth_addy)   
    let (repay_erc) = Math64x61_convert_from(repay,usdc_decimals)
    with_attr error_message("Not sufficient funds to repay."):
        assert_le(repay_erc,usdc_user)
    end
    
    # ai split
    let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
    let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    
    # repay split loan vs interest
    let (temp1) = Math64x61_div(notional,acrrued_notional)
    let (loan_total_change) = Math64x61_mul(repay,temp1)
    let (temp2) = Math64x61_div(accrued_interest,acrrued_notional)
    let (accrued_interest_change) = Math64x61_mul(repay,temp2)
    # work out splits for AI
    let (accrued_interest_lp) = Math64x61_mul(lp_split, accrued_interest_change)
    let (accrued_interest_if) = Math64x61_mul(if_split, accrued_interest_change)
    let (accrued_interest_gt) = Math64x61_mul(gt_split, accrued_interest_change)

    # deal with partial repayment by aportioning payment
    let (repay_erc) = Math64x61_convert_from(repay,usdc_decimals) 
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, repay_erc)     
    let (accrued_interest_if_erc) = Math64x61_convert_from(accrued_interest_if, usdc_decimals) 
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, if_addy, accrued_interest_if_erc)
    
    #update CZCore    
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (new_loan_total) = Math64x61_sub(loan_total, loan_total_change)
    let (new_capital_total) = Math64x61_add(capital_total, accrued_interest_lp)
    let (new_reward_total) = Math64x61_add(reward_total, accrued_interest_gt)
    CZCore.set_loan_total(czcore_addy, new_capital_total, new_loan_total, new_reward_total)
    
    let (new_notional) = Math64x61_sub(acrrued_notional, repay)
    let (new_start_ts) = Math64x61_ts()
    
    if new_notional == 0:
        decrease_collateral(collateral)
        CZCore.set_cb_loan(czcore_addy, user, 0, 0, 0, 0, 0, 0)
        #event
        loan_change.emit(addy=user, notional=0, collateral=0,start_ts=0,end_ts=0,rate=0)    
        return (1)
    else:
        CZCore.set_cb_loan(czcore_addy, user, 1, new_notional, collateral, new_start_ts, end_ts, rate)
        #event
        loan_change.emit(addy=user, notional=new_notional, collateral=collateral,start_ts=new_start_ts,end_ts=end_ts,rate=rate)   
        return (1)
    end
end

# repay loan in full
@external
func repay_loan_full{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() - > (res : felt):
    
    # addys and check if existing loan
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate, accrued_interest) = get_loan_details(user)
        
    # new notional = old notional + ai -repay
    let (acrrued_notional) = Math64x61_add(notional,accrued_interest)
    res = repay_loan_partial(acrrued_notional)
    return(res)
end

# increase collateral
@external
func increase_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(collateral : felt) - > (res : felt):
    
    # Verify that the user has sufficient funds before call
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (weth_user) = Erc20.ERC20_balanceOf(weth_addy, user)   
    let (weth_quant_decimals) = Erc20.ERC20_decimals(weth_addy)   
    let (collateral_erc) = Math64x61_convert_from(collateral,weth_quant_decimals) 
    with_attr error_message("User does not have sufficient funds."):
       assert_le(collateral_erc, weth_user)
    enn
    
    # transfer the actual WETH tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)
    let (has_loan, notional, old_collateral, start_ts, end_ts, rate, accrued_interest) = get_loan_details(user)
    let (new_collateral) = Math64x61_add(collateral, old_collateral)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, new_collateral, start_ts, end_ts, rate)
    loan_change.emit(addy=user, notional=notional, collateral=new_collateral,start_ts=start_ts,end_ts=end_ts,rate=rate)  
    return(1)
end

# decrease collateral
@external
func decrease_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(collateral : felt) - > (res : felt):
    
    # Verify amount positive
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()    
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    with_attr error_message("Collateral withdrawal should be a positive amount."):
       assert_nn(collateral)
    enn
    
    # check withdrawal would not make loan insolvent
    let (has_loan, notional, old_collateral, start_ts, end_ts, rate, accrued_interest) = get_loan_details(user)
    let (acrrued_notional) = Math64x61_add(notional,accrued_interest)
    let (new_collateral) = Math64x61_sub(old_collateral, collateral)
    let (weth_ltv) = Settings.get_weth_ltv(settings_addy)
    # call oracle price for collateral
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    let (weth_price) = Oracle.get_weth_price(oracle_addy)
    let (weth_price_decimals) = Oracle.get_weth_decimals(oracle_addy)
    let (temp1) = Math64x61_convert_to(weth_price,weth_price_decimals)
    let (temp2) = Math64x61_mul(temp1,new_collateral)
    let (temp3) = Math64x61_mul(temp2,weth_ltv)
    with_attr error_message("Not sufficient collateral for loan"):
        assert_le(acrrued_notional,temp3)
    end
        
    let (weth_quant_decimals) = Erc20.ERC20_decimals(weth_addy)   
    let (collateral_erc) = Math64x61_convert_from(collateral,weth_quant_decimals) 
    # transfer the actual WETH tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, czcore_addy, user, collateral_erc)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, new_collateral, start_ts, end_ts, rate)
    loan_change.emit(addy=user, notional=notional, collateral=new_collateral,start_ts=start_ts,end_ts=end_ts,rate=rate)  
    return(1)
end

# refinance laon
@external
func refinance_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(loanID : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt,pp_data : felt*) - > (res : felt):
    
    # addys and check if existing loan
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, old_notional, old_collateral, old_start_ts, old_end_ts, old_rate, accrued_interest) = get_loan_details(user)
    with_attr error_message("User does not have an existing loan."):
        assert has_loan = 1
    end
    
    # pp data should be passed as follows
    # [ signed_loanID_r , signed_loanID_s , signed_rate_r , signed_rate_s , rate , pp_pub , ..... ]
    let (loanID_hash) = hash2{hash_ptr=pedersen_ptr}(loanID, 0)
    let (rate_array : felt*) = alloc()
    let (pp_pub_array : felt*) = alloc()

    # iterate thru pp data - verify the pp's signature.
    let (rate_array_len, rate_array, pp_pub_array_len, pp_pub_array) = check_pricing(pp_data_len, pp_data, loanID_hash)
    
    # check eno pp for pricing, settings has min_pp
    let (setting_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (min_pp) = Settings.get_min_pp(setting_addy)
    with_attr error_message("Not enough PPs for valid pricing."):
        assert_le(min_pp,rate_array_len)
    end
    
    # order the rates and find the median
    let (len_ordered, ordered, len_index, index) = sort_index(rate_array_len, rate_array, rate_array_len, rate_array)
    let (median, _) = unsigned_div_rem(len_ordered, 2)

    # later randomly select 75% of the PPs, also deal with median when even number of PP
    let (median_rate) = ordered[median]    
    # get index of rate to find winning PP
    let (winning_position) = index[median]
    let (winning_pp) = pp_pub_array[winning_position]

    # call oracle price for collateral
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    let (weth_price) = Oracle.get_weth_price(oracle_addy)
    let (weth_price_decimals) = Oracle.get_weth_decimals(oracle_addy)

    # get ltv from setting
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (weth_ltv) = Settings.get_weth_ltv(settings_addy)
    # test sufficient collateral to proceed vs notional of loan
    let (temp1) = Math64x61_convert_to(weth_price,weth_price_decimals)
    let (temp2) = Math64x61_mul(temp1,collateral)
    let (temp3) = Math64x61_mul(temp2,WETH_ltv)
    with_attr error_message("Not sufficient collateral for loan"):
        assert_le(notional,temp3)
    end
    
    # Verify that the user has sufficient funds before call
    let (weth_user) = Erc20.ERC20_balanceOf(weth_addy, user)   
    let (weth_quant_decimals) = Erc20.ERC20_decimals(weth_addy)  
    let (change_collateral) = Math64x61_sub(collateral,old_collateral) 
    let (change_collateral_erc) = Math64x61_convert_from(change_collateral,weth_quant_decimals) 
    with_attr error_message("User does not have sufficient funds."):
       assert_le(change_collateral, weth_user)
    enn
    
    # check below utilization level post loan
    let (lp_total,capital_total,loan_total,insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (stop) = Settings.get_utilization(settings_addy)
    let (old_accrued_notional) = Math64x61_add(old_notional,accrued_interest) 
    let (change_notional) = Math64x61_sub(notional,old_accrued_notional) 
    let (temp4) = Math64x61_add(change_notional,loan_total)
    let (temp5) = Math64x61_div(temp4,capital_total)
    with_attr error_message("Utilization to high, cannot refinance loan."):
       assert_le(temp5, stop)
    enn
    
    # check end time less than setting max loan time
    let (block_ts) = Math64x61_ts()
    let (max_term) = Settings.get_max_loan_term(settings_addy)
    let (temp6) = Math64x61_add(block_ts,max_term)
    with_attr error_message("Loan term should be within term range."):
       assert_in_range(end_ts, block_ts, temp6)
    enn

    # check loan amount within correct ranges
    let (min_loan,max_loan) = Settings.get_min_max_loan(settings_addy)
    with_attr error_message("Notional should be within min max loan range."):
       assert_in_range(notional, min_loan, max_loan)
    enn

    # add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (temp7) = Math64x61_add(fee,Math64x61_ONE)
    let (change_notional_with_fee) = Math64x61_mul(temp7,change_notional)

    # transfer collateral to CZCore and transfer USDC to user
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (change_notional_erc) = Math64x61_convert_from(change_notional,usdc_decimals) 
    let (origination_fee) = Math64x61_sub(change_notional_with_fee,change_notional)
    let (temp8) = Math64x61_mul(origination_fee,pp_split)
    let(fee_erc_pp) = Math64x61_convert_from(temp8,usdc_decimals)
    let (temp9) =  Math64x61_mul(origination_fee,if_split)
    let (fee_erc_if) = Math64x61_convert_from(temp9,usdc_decimals)
    let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    
    let (new_notional_with_fee) = Math64x61_add(old_accrued_notional,change_notional_with_fee)

    # transfer the actual USDC tokens to user - ERC decimal version
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, user, change_notional_erc)
    # transfer pp and if
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, winning_pp, fee_erc_pp)
    CZCore.ERC20_transferFrom(czcore_addy, usdc_addy, czcore_addy, if_addy, fee_erc_if)
    # transfer the actual WETH tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, change_collateral_erc)
    #update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, new_notional_with_fee, collateral, block_ts, end_ts, median_rate, 0)
    let (lp_total, capital_total, loan_total, insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (new_loan_total) = Math64x61_add(loan_total,change_notional_with_fee)
    CZCore.set_loan_total(czcore_addy, new_loan_total)
    
    #event
    loan_change.emit(addy=user, notional=notional_with_fee, collateral=collateral,start_ts=block_ts,end_ts=end_ts,rate=median_rate)
    return (1)
end

# check all PPs are valid - check sigs vs. signed loan and sigs vs. signed rate provided
func check_pricing{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,ecdsa_ptr : SignatureBuiltin*}
        (length : felt, array : felt*, loan_hash : felt) -> (r_array_len : felt, r_array : felt*, p_array_len : felt, p_array : felt*):
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
func get_min_value_above{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}
        (x : felt, array_len : felt, array : felt*) -> (y : felt, index : felt):
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
func sort_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x_len : felt, x : felt*, y_len : felt, y : felt*) -> (
        z_len : felt, z : felt*, i_len : felt, i : felt*):
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
