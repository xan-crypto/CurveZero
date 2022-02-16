# CB contract

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check)
from starkware.starknet.common.syscalls import get_block_timestamp
from InterfaceAll import TrustedAddy, CZCore, Settings
from Math.Math64x61 import (
    Math64x61_mul, Math64x61_div, Math64x61_pow, Math64x61_pow_frac, Math64x61_sqrt, Math64x61_exp,
    Math64x61_ln,Math64x61_sub,Math64x61_add)

##################################################################
# constants 
const Math64x61_FRACT_PART = 2 ** 61
const Math64x61_ONE = 1 * Math64x61_FRACT_PART
# 24*60*60*365.25
const year_secs = 31557600 * Math64x61_ONE

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        deployer : felt):
    deployer_addy.write(deployer)
    return ()
end

# who is deployer
@view
func get_deployer_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        addy : felt):
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
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        addy : felt):
    let (addy) = trusted_addy.read()
    return (addy)
end

# set the trusted contract addy
@external
func set_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        addy : felt):
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
func get_loan_accured_interest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        user : felt) -> (
        has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt,
        rate : felt, accrued_interest : felt):
    
    alloc_locals
    # Obtain the address of the czcore contract
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    
    # get user loan
    let (has_loan,notional,collateral,start_ts,end_ts,rate) = CZCore.get_cb_loan(czcore_addy,user)
    
    # calc accrued interest
    let (block_ts) = get_block_timestamp()
    tempvar block_ts_64x61 = block_ts * Math64x61_ONE
    
    # if no loan
    if has_loan == 0:
        return (has_loan,notional,collateral,start_ts,end_ts,rate,0)
    else:
        let (ts_diff) = Math64x61_sub(block_ts_64x61,start_ts)
        let (year_frac) = Math64x61_div(ts_diff,year_secs)
        let (accrual_factor) = Math64x61_add(Math64x61_ONE,rate)
        let (actual_accrual) = Math64x61_pow_frac(accrual_factor,year_frac)
        let (notional_accrual) = Math64x61_mul(notional,actual_accrual)
        let (accrued_interest) = Math64x61_sub(notional_accrual,notional)
        return (has_loan,notional,collateral,start_ts,end_ts,rate,accrued_interest)
    end
end


# accecpt a loan
# set loan terms
@external
func accept_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        loanID : felt, notional : felt, collateral : felt, end_ts : felt, pp_data_len : felt, pp_data : felt*):
    
    # pp data should be passed as follows
    # [ signed_loanID_r , signed_loanID_s , signed_rate_r , signed_rate_s , rate , pp_pub , ..... ]
    
    let (loanID_hash) = hash2{hash_ptr=pedersen_ptr}(loanID, 0)
    let (rate_array : felt*) = alloc()
    let (pp_pub_array : felt*) = alloc()
    
    
    # iterate thru pp data
    # Verify the pp's signature.
    
    # verify_all_pp(pp_data,pp_data_len)
    
    # pp 1
    let signed_loanID_r = pp_data[0] 
    let signed_loanID_s = pp_data[1] 
    let signed_rate_r = pp_data[2] 
    let signed_rate_s = pp_data[3] 
    let rate = pp_data[4]     
    let pp_pub = pp_data[5]
    
    verify_ecdsa_signature(message=loanID_hash,public_key=pp_pub,signature_r=signed_loanID_r,signature_s=signed_loanID_s)
    let (rate_hash) = hash2{hash_ptr=pedersen_ptr}(rate, 0)
    verify_ecdsa_signature(message=rate_hash,public_key=pp_pub,signature_r=signed_rate_r,signature_s=signed_rate_s)
    
    assert [rate_array] = rate
    assert [pp_pub_array] = pp_pub

    # pp 2
    let signed_loanID_r = pp_data[6] 
    let signed_loanID_s = pp_data[7] 
    let signed_rate_r = pp_data[8] 
    let signed_rate_s = pp_data[9] 
    let rate = pp_data[10]     
    let pp_pub = pp_data[11]
    
    verify_ecdsa_signature(message=loanID_hash,public_key=pp_pub,signature_r=signed_loanID_r,signature_s=signed_loanID_s)
    let (rate_hash) = hash2{hash_ptr=pedersen_ptr}(rate, 0)
    verify_ecdsa_signature(message=rate_hash,public_key=pp_pub,signature_r=signed_rate_r,signature_s=signed_rate_s)
    
    assert [rate_array + 1] = rate
    assert [pp_pub_array + 1] = pp_pub


    
        
    # call oracle price for collateral
    let (_trusted_addy) = trusted_addy.read()
    let (oracle_addy) = TrustedAddy.get_oracle_addy(_trusted_addy)
    Oracle.update_weth_price(oracle_addy)

    # get ltv from setting

    # test sufficient collateral to proceed vs notional of loan

    # get blockstamp time for start time

    # check end time less than setting max loan time

    # iterate to pp and create list of valid

    # check eno pp for pricing settings has min_pp

    # set rate to median pp price

    # check authorised caller

    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    CZCore.set_cb_loan(czcore_addy, user, has_loan, notional, collateral, start_ts, end_ts, rate, refinance)
    return ()
end

# check pp pricing
func check_pricing(array : felt*, length : felt, loanID_hash : felt) -> (r_array_len : felt, r_array : felt*, p_array_len : felt, p_array : felt*):
       
    if length == 0:
        let (r_array : felt*) = alloc()
        let (p_array : felt*) = alloc()        
        return (0,r_array,0,p_array)
    end

    let (r_array_len,r_array,p_array_len,p_array) = check_pricing(array=array + 6, length=length - 6, loanID_hash)
    
    let signed_loanID_r = array[0] 
    let signed_loanID_s = array[1] 
    let signed_rate_r = array[2] 
    let signed_rate_s = array[3] 
    let rate = array[4]     
    let pp_pub = array[5]
    
    verify_ecdsa_signature(message=loanID_hash,public_key=pp_pub,signature_r=signed_loanID_r,signature_s=signed_loanID_s)
    let (rate_hash) = hash2{hash_ptr=pedersen_ptr}(rate, 0)
    verify_ecdsa_signature(message=rate_hash,public_key=pp_pub,signature_r=signed_rate_r,signature_s=signed_rate_s)
    
    assert [rate_array + 1] = rate
    assert [pp_pub_array + 1] = pp_pub
    
    # This part of the function is first reached when length=0.
    # The sum begins. This is the sequence: 1, 1+23 then 24+2
    let sum = [array] + current_sum
    # The return function targets the body of this function
    # 3 times before returning to the body of read_sum().
    return (sum)
end

