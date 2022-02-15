# CB contract

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import (Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check)
from starkware.starknet.common.syscalls import get_block_timestamp
from InterfaceAll import (TrustedAddy,CZCore,Settings)
from Math.Math64x61 import (Math64x61_mul,Math64x61_div,Math64x61_pow,Math64x61_sqrt,Math64x61_exp,Math64x61_ln)

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy 
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(deployer : felt):
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
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
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
# accecpt a loan
# repay a loan
# refinance a loan



