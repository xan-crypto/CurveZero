# PP contract

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address

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

# events keeping tracks of what happened
@event
func pp_token_change(addy : felt, pp_status):
end

# promote user to PP
# demote user from PP
