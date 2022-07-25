####################################################################################
# @title Oracle contract
# @dev this contract is a dummy test contract for oracle pricing on WETH
# we use this for testing only
# this contract is not apart of CurveZero
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_zero
from Functions.Checks import check_is_owner

@storage_var
func oracle_name() -> (name: felt):
end

@storage_var
func oracle_symbol() -> (symbol: felt):
end

@storage_var
func oracle_decimals() -> (decimals: felt):
end

@storage_var
func oracle_price() -> (price: felt):
end

@storage_var
func owner_addy() -> (addy : felt):
end

@view
func get_owner_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = owner_addy.read()
    return (addy)
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(name: felt,symbol: felt,owner: felt):
    oracle_name.write(name)
    oracle_symbol.write(symbol)
    oracle_decimals.write(18)
    oracle_price.write(1000000000000000000000)
    owner_addy.write(owner)
    return ()
end

@view
func get_oracle_name{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (name: felt):
    let (name) = oracle_name.read()
    return (name)
end

@view
func get_oracle_symbol{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (symbol: felt):
    let (symbol) = oracle_symbol.read()
    return (symbol)
end

@view
func get_oracle_decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (decimals: felt):
    let (decimals) = oracle_decimals.read()
    return (decimals)
end

@view
func get_oracle_price{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (price: felt):
    let (price) = oracle_price.read()
    return (price)
end

@external
func set_oracle_price{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(price : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    oracle_price.write(price)
    return ()
end