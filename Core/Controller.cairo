# controller for pausing slashing IF payout

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
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

# paused = 1 unpaused = 0
@storage_var
func paused() -> (res : felt):
end

# pause (pause new loans, refin/repay allowed, pause LP PP new/redeem, pause GT stake/unstake)
@external
func set_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}:
    let (caller) = get_caller_address()
    let (deployer) = deployer_addy.read()
    with_attr error_message("Only deployer can pause system."):
        assert caller = deployer
    end
    paused.write(1)
    return (1)
end

# unpause
@external
func set_unpaused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}:
    let (caller) = get_caller_address()
    let (deployer) = deployer_addy.read()
    with_attr error_message("Only deployer can unpause system."):
        assert caller = deployer
    end
    paused.write(0)
    return (0)
end
