# main contract
# all interactions with reserves or state should flow through here

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

# addy of the trusted addy contract
@storage_var
func trusted_addy() -> (addy : felt):
end

# set the addy of the trusted addy contract on deploy
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(_trusted_addy : felt):
    trusted_addy.write(_trusted_addy)
    return ()
end

# interface to trusted addys contract
@contract_interface
namespace TrustedAddy:
    func get_lp_addy() -> (addy : felt):
    end
    func get_controller_addy() -> (addy : felt):
    end
end

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
    let (trust_contract) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(trust_contract)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (controller) = TrustedAddy.get_controller_addy(trust_contract)
    let (paused) = Controller.is_paused(controller)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    lp_balances.write(user,amount)
    return ()
end

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
    let (trust_contract) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(trust_contract)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
     # check if paused
    let (controller) = TrustedAddy.get_controller_addy(trust_contract)
    let (paused) = Controller.is_paused(controller)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    lp_total.write(amount)
    return ()
end

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
    let (trust_contract) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(trust_contract)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (controller) = TrustedAddy.get_controller_addy(trust_contract)
    let (paused) = Controller.is_paused(controller)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    capital_total.write(amount)
    return ()
end

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
    let (trust_contract) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(trust_contract)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (controller) = TrustedAddy.get_controller_addy(trust_contract)
    let (paused) = Controller.is_paused(controller)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    loan_total.write(amount)
    return ()
end

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
    let (trust_contract) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(trust_contract)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    insolvency_shortfall.write(amount)
    return ()
end
