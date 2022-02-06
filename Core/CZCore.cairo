# main contract
# all interactions with reserves or state should flow through here

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

# interface to trusted addys contract
@contract_interface
namespace TrustedAddy:
    func get_lp_addy() -> (addy : felt):
    end
end

# LP token balances by user
@storage_var
func lp_balances(user : felt) -> (res : felt):
end

# Total LP tokens in issue
@storage_var
func lp_total() -> (res : felt):
end

# Total USDC capital
@storage_var
func capital_total() -> (res : felt):
end

# Total USDC loans
@storage_var
func loan_total() -> (res : felt):
end

# Insolvency shortfall
@storage_var
func insolvency_shortfall() -> (res : felt):
end

# Returns the balance of the given user.
@view
func get_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (res : felt):
    let (res) = lp_balances.read(user=user)
    return (res)
end

@view
func get_loan_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = loan_total.read()
    return (res)
end

@view
func get_capital_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = capital_total.read()
    return (res)
end

@view
func get_lp_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = lp_total.read()
    return (res)
end
