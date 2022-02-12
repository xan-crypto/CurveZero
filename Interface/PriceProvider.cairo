# PP contract

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address

##################################################################
# needed so that deployer can point PP contract to CZCore
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the trusted addy contract on deploy
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
# CZCore addy and interface, only deployer can point PP contract to CZCore
# addy of the CZCore contract
@storage_var
func czcore_addy() -> (addy : felt):
end

# set the CZCore contract addy
@external
func set_czcore_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addy : felt):
    let (caller) = get_caller_address()
    let (deployer) = deployer_addy.read()
    with_attr error_message("Only deployer can change the CZCore addy."):
        assert caller = deployer
    end
    czcore_addy.write(addy)
    return ()
end

# interface to trusted addys contract
@contract_interface
namespace CZCore:
    func get_pp_status(user : felt) -> (res : felt):
    end
    func set_pp_promote(user : felt):
    end
    func set_pp_demote(user : felt):
    end
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
# promote user to PP
# demote user from PP
