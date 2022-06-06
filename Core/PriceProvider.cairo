####################################################################################
# @title PriceProvider contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - request the simple interest rate for any timestamp
# if the timestamp is prior the first ts in the inst array => the rate of the first inst is given (aave ON)
# if the timestamp is after the last ts in the inst array => the rate of the last inst is fiven (last spot futs basis + adjustment)
# the rate return should always be >= to the rate of the first inst (implied flat for upward sloping yield curve)
# The Oracle PP will store the latest array of the follow tuples [ inst_id, end_ts, rate ... ]
# This contract addy will be stored in the TrustedAddy contract
# This contract will be called from the CB contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_le
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math10xx8 import Math10xx8_ts, Math10xx8_sub
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
# @dev get rate from curve
# @param input is 
# - the timestamp of rate needed
# @return
# - the rate at that timestamp
# flat before start pt and after end pt
####################################################################################
@view
func get_rate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(ts : felt) -> (rate : felt):
    alloc_locals
    # @dev check if status not 1 already - existing pp
    let (_trusted_addy) = trusted_addy.read()
    let (oracle_pp_addy) = TrustedAddy.get_oracle_pp_addy(_trusted_addy)
    let (id_1, ts_1, price_1, id_2, ts_2, price_2) = CZCore.get_pp_status(czcore_addy, user)
    
    # @dev check that user has eno LP tokens
    if is_le(ts, ts_1) == 1:
        return(price_1)
    end
    if is_le(ts, ts_2) == 1:
        let (int_rate) = interpolate(ts_1, price_1, ts_2, price_2, ts)
        return(int_rate)
    else:
        return(price_2)
    end
end

####################################################################################
# @dev interpolate function
####################################################################################
func interpolate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(x1 : felt, y1 : felt, x2 : felt, y2 : felt, x : felt) -> (y : felt):
    alloc_locals

    if is_le(y1, y2) == 1:
        let (y_diff) = Math10xx8_sub(y2, y1)
        let (x_diff) = Math10xx8_sub(x2, x1)
        let (x_int) = Math10xx8_sub(x, x1)
        let (per) = Math10xx8_div(x_int, x_diff)
        let (add) = Math10xx8_mul(per, y_diff)
        let (res) = Math10xx8_add(y1, add)
        return(res)
    else:
        let (y_diff) = Math10xx8_sub(y1, y2)
        let (x_diff) = Math10xx8_sub(x2, x1)
        let (x_int) = Math10xx8_sub(x, x1)
        let (per) = Math10xx8_div(x_int, x_diff)
        let (sub) = Math10xx8_mul(per, y_diff)
        let (res) = Math10xx8_sub(y1, sub)
        return(res)
    end
end