# PP contract

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import (TrustedAddy,CZCore)

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
# need to emit PP events so that we can do reporting / dashboard to monitor system
# need to emit amount of lp and cz change, to recon vs. total lp cz holdings for pp
# events keeping tracks of what happened
@event
func pp_token_change(addy : felt, pp_status : felt, lp_change : felt, cz_change : felt):
end

##################################################################
# PP contract functions
# view user PP status
@view
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt) -> (lp_token : felt, cz_token : felt, res : felt):
    
    # Obtain the address of the czcore contract
    let (_trusted_addy) = trusted_addy.read()
    let (_czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    
    # check pp status and tokens 
    let (_pp_status) = CZCore.get_pp_status(_czcore_addy,user)
    return (_pp_status)
end


# promote user to PP
# demote user from PP
