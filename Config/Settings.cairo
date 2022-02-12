# Settings contract

# imports
%lang starknet
%builtins pedersen range_check
from starkware.cairo.common.cairo_builtins import HashBuiltin
from InterfaceAll import (TrustedAddy)

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy 
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(deployer : felt):
    deployer_addy.write(deployer)
    # set initial amounts for becoming pp - NB NB change this later
    pp_token_requirement.write(5000,5000)
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
# functions to set the amount of LP CZ tokens needed to become a PP
@storage_var
func pp_token_requirement() -> (require : (felt, felt)):
end

# returns the current requirement to become PP
@view
func get_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (require : (felt, felt)):
    let (res) = pp_token_requirement.read()
    return (res)
end

# set new token requirement to become PP
@external
func set_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_require : felt, cz_require : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = _controller_addy
    end
    pp_token_requirement.write((lp_require,cz_require))
    return ()
end
