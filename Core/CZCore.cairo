# CZCore contract
# all interactions with reserves or state should flow through here

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import (Uint256)
from InterfaceAll import (TrustedAddy,Controller,ERC20)

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
# this is a pass thru function to the ERC-20 token contract
@external
func erc20_transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, sender: felt, recipient: felt, amount: Uint256):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    ERC20.ERC20_transferFrom(erc_addy,sender=sender,recipient=recipient,amount=amount)
    return ()
end

##################################################################
# functions to set and get lp tokens by user
# the LP token balances by user
@storage_var
func lp_balances(user : felt) -> (res : felt):
end

# returns the balance of the given user
@view
func get_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (res : felt):
    let (res) = lp_balances.read(user=user)
    return (res)
end

# set the balance of the given user
@external
func set_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, amount : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    lp_balances.write(user,amount)
    return ()
end

##################################################################
# total LP tokens in issue
@storage_var
func lp_total() -> (res : felt):
end

# returns the total LP tokens in issue
@view
func get_lp_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = lp_total.read()
    return (res)
end

# set the LP total
@external
func set_lp_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
     # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    lp_total.write(amount)
    return ()
end

##################################################################
# Total USDC capital
@storage_var
func capital_total() -> (res : felt):
end

# returns the total USDC capital
@view
func get_capital_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = capital_total.read()
    return (res)
end

# set the USD capital total
@external
func set_capital_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    capital_total.write(amount)
    return ()
end

##################################################################
# Total USDC loans
@storage_var
func loan_total() -> (res : felt):
end

# returns the total USDC loans
@view
func get_loan_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = loan_total.read()
    return (res)
end

# set the USD loan total
@external
func set_loan_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    loan_total.write(amount)
    return ()
end

##################################################################
# Insolvency shortfall
@storage_var
func insolvency_shortfall() -> (res : felt):
end

# returns the insolvency shortfall
@view
func get_insolvency_shortfall{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = insolvency_shortfall.read()
    return (res)
end

# set the insolvency_shortfall
@external
func set_insolvency_shortfall{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    insolvency_shortfall.write(amount)
    return ()
end

##################################################################
# functions to promote and demote and view pp
# the PP status by user
@storage_var
func pp_status(user : felt) -> (status : (felt, felt, felt)):
end

# returns the PP status of the given user
@view
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (status: (felt, felt, felt)):
    let (res) = pp_status.read(user=user)
    return (res)
end

# promote user to pp and lock lp and cz tokens
@external
func set_pp_promote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, lp_user : felt, lp_require : felt, cz_require : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_pp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end

    # reduce lp balance of user
    lp_balances.write(user,lp_user-lp_require)
    
    # update the pp status
    pp_status.write(user,(lp_require,cz_require,0))
    return ()
end

# demote user from pp and return lp and cz tokens
@external
func set_pp_demote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, lp_user : felt, lp_locked : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_pp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.is_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end

    # reduce lp balance of user
    lp_balances.write(user,lp_user+lp_locked)
    
    # update the pp status
    pp_status.write(user,(0,0,0))
    return ()
end
