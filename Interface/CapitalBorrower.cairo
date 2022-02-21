# CB contract
# all numbers passed into contract must be Math64x61 type

# imports
%lang starknet
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import unsigned_div_rem, assert_in_range
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, ERC20
from Math.Math64x61 import (Math64x61_mul, Math64x61_div, Math64x61_pow_frac, Math64x61_sub, Math64x61_add, Math64x61_ts)

##################################################################
# constants
# 24*60*60*365.25
Math64x61_ONE = 2 ** 61
const year_secs = 31557600 * 2 ** 61

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(deployer : felt):
    deployer_addy.write(deployer)
    return ()
end

# who is deployer
@view
func get_deployer_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = deployer_addy.read()
    return (addy)
end

##################################################################
# Trusted addy, only deployer can point contract to Trusted Addy contract
# addy of the Trusted Addy contract
@storage_var
func trusted_addy() -> (addy : felt):
end

# get the trusted contract addy
@view
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = trusted_addy.read()
    return (addy)
end

# set the trusted contract addy
@external
func set_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addy : felt):
    let (caller) = get_caller_address()
    let (deployer) = deployer_addy.read()
    with_attr error_message("Only deployer can change the Trusted addy."):
        assert caller = deployer
    end
    trusted_addy.write(addy)
    return ()
end

##################################################################
# need to emit CB events so that we can build the loan book for liquidation/monitoring/dashboard
# events keeping tracks of what happened
@event
func new_loan():
end

@event
func repay_loan():
end

@event
func refinance_loan():
end

##################################################################
# CB contract functions
# query a users loan
@view
func get_loan_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
        has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, accrued_interest : felt):
    
    alloc_locals
    # calc accrued interest and return loan details
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, notional, collateral, start_ts, end_ts, rate) = CZCore.get_cb_loan(czcore_addy, user)
    let (block_ts) = Math64x61_ts()

    # if no loan
    if has_loan == 0:
        return (has_loan, notional, collateral, start_ts, end_ts, rate, 0)
    else:
        let (temp1) = Math64x61_sub(block_ts, start_ts)
        let (temp2) = Math64x61_div(temp1, year_secs)
        let (temp3) = Math64x61_add(Math64x61_ONE, rate)
        let (temp4) = Math64x61_pow_frac(temp3, temp2)
        let (temp5) = Math64x61_mul(notional, temp4)
        let (accrued_interest) = Math64x61_sub(temp5, notional)
        return (has_loan, notional, collateral, start_ts, end_ts, rate, accrued_interest)
    end
end

# accecpt a loan / set loan terms
@external
func accept_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(loanID : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt,pp_data : felt*) - > (res : felt):
    
    # addys and check if existing loan
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (has_loan, _) = CZCore.get_cb_loan(czcore_addy, user)
    with_attr error_message("User already has an existing loan, refinance instead."):
        assert has_loan = 0
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
    CZcore.update_weth_price(czcore_addy,oracle_addy)
    let (WETH_price) = CZcore.get_weth_price(czcore_addy,oracle_addy)

    # get ltv from setting
    let (weth_addy) = TrustedAddy.get_weth_addy(_trusted_addy)
    let (WETH_ltv) = Settings.get_weth_ltv(settings_addy)
    # test sufficient collateral to proceed vs notional of loan
    let (weth_decimals) = CZCore.erc20_decimals(czcore_addy,weth_addy)
    let (temp1) = Math64x61_convert_to(WETH_price,weth_decimals)
    let (temp2) = Math64x61_mul(temp1,collateral)
    let (temp3) = Math64x61_mul(temp2,WETH_ltv)
    with_attr error_message("Not sufficient collateral for loan"):
        assert_le(notional,temp3)
    end
    
    # get user weth balance - not Math64x61 types
    let (WETH_user) = CZCore.erc20_balanceOf(czcore_addy, weth_addy, user)   
    # do decimal conversion so comparing like with like
    let (collateral_erc) = Math64x61_convert_from(collateral,weth_decimals) 
    
    # Verify that the user has sufficient funds before call
    with_attr error_message("User does not have sufficient funds."):
       assert_le(collateral_erc, WETH_user)
    enn
    
    # check below utilization level
    let (lp_total,capital_total,loan_total,insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (start,stop) = Settings.get_utilization(settings_addy)
    # check that post loan util level will not be above stop
    let (temp3) = Math64x61_add(notional,loan_total)
    let (temp4) = Math64x61_div(temp3,capital_total)
    with_attr error_message("Utilization to high, cannot issue loan."):
       assert_le(temp4, stop)
    enn
    
    # get blockstamp time for start time
    let (block_ts) = get_block_timestamp()
    # all numbers are 64x61 type
    tempvar block_ts_64x61 = block_ts * Math64x61_ONE
    
    # check end time less than setting max loan time
    let (max_term) = Settings.get_max_term(settings_addy)
    let (temp5) = Math64x61_add(block_ts_64x61,max_term)
    with_attr error_message("Loan term should be with term range."):
       assert_in_range(end_ts, block_ts_64x61, temp5)
    enn

    # add origination fee
    let (fee, pp_split, if_split) = Settings.get_origination_fee(settings_addy)
    let (temp6) = Math64x61_add(fee,Math64x61_ONE)
    let (notional_with_fee) = Math64x61_mul(temp6,notional)

    # transfer collateral to CZCore and transfer USDC to user
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = CZCore.erc20_decimals(czcore_addy,usdc_addy)
    
    let (notional_erc) = Math64x61_convert_from(notional,usdc_decimals) 
    let (origination_fee) = Math64x61_sub(notional_with_fee,notional)
    let (temp8) = Math64x61_mul(origination_fee,pp_split)
    let(fee_erc_pp) = Math64x61_convert_from(temp8,usdc_decimals)
    let (temp9) =  Math64x61_mul(origination_fee,if_split)
    let (fee_erc_if) = Math64x61_convert_from(temp9,usdc_decimals)
    let(if_addy) = TrustedAddy.get_if_addy(_trusted_addy)

    # transfer the actual USDC tokens to user - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, czcore_addy, user, notional_erc)
    # transfer pp and if
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, czcore_addy, winning_pp, fee_erc_pp)
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, czcore_addy, if_addy, fee_erc_if)

    # transfer the actual WETH tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, weth_addy, user, czcore_addy, collateral_erc)

    #update CZCore
    CZCore.set_cb_loan(czcore_addy, user, 1, notional_with_fee, collateral, block_ts_64x61, end_ts, median_rate, 0)
    return (1)
end

# check all PPs are valid
# check sigs vs. signed loanID and sigs vs. signed rate provided
func check_pricing{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        ecdsa_ptr : SignatureBuiltin*}(length : felt, array : felt*, loanID_hash : felt) -> (
        r_array_len : felt, r_array : felt*, p_array_len : felt, p_array : felt*):
    # create arrays at last step
    if length == 0:
        let (r_array : felt*) = alloc()
        let (p_array : felt*) = alloc()
        return (0, r_array, 0, p_array)
    end

    # recursive call
    let (r_array_len, r_array, p_array_len, p_array) = check_pricing(
        length - 6, array + 6, loanID_hash)

    # validate that the PP signed both loanID and rate correctly
    let signed_loanID_r = array[0]
    let signed_loanID_s = array[1]
    let signed_rate_r = array[2]
    let signed_rate_s = array[3]
    let rate = array[4]
    let pp_pub = array[5]

    verify_ecdsa_signature(
        message=loanID_hash,
        public_key=pp_pub,
        signature_r=signed_loanID_r,
        signature_s=signed_loanID_s)
    let (rate_hash) = hash2{hash_ptr=pedersen_ptr}(rate, 0)
    verify_ecdsa_signature(
        message=rate_hash, public_key=pp_pub, signature_r=signed_rate_r, signature_s=signed_rate_s)

    # add to new arrays
    assert [r_array + r_array_len] = rate
    assert [p_array + p_array_len] = pp_pub
    return (r_array_len + 1, r_array, p_array_len + 1, p_array)
end

# this function returns to min value of an array and the index thereof
func get_min_value_above{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : felt, array_len : felt, array : felt*) -> (y : felt, index : felt):
    # alloc()
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

# this function sorts an array of size n from high to low
# need this for the median calc for PPs
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
