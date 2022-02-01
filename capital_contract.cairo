%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address

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

# Insurance shortfall
@storage_var
func insurance_shortfall() -> (res : felt):
end

# Issue LP tokens to user
@external
func deposit_USDC_vs_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(depo_USD : felt) -> (lp : felt):

    # Verify that the amount is positive.
    with_attr error_message("Amount must be positive."):
        assert_nn(depo_USD)
    end

    # Obtain the address of the account contract.
    let (user) = get_caller_address()
	
    # check for existing lp tokens and capital
    let (_lp_total) = lp_total.read()
    let (_capital_total) = capital_total.read()
    # calc new total capital
    let new_capital_total = _capital_total + depo_USD

    # calc new lp total and new lp issuance
    if _lp_total == 0:
        let new_lp_total = depo_USD
        let new_lp_issuance = depo_USD

        # store all new data
        lp_total.write(new_lp_total)
        capital_total.write(new_capital_total)

        let (res) = lp_balances.read(user)
        lp_balances.write(user, res + new_lp_issuance)
        return (new_lp_issuance)
    else:	
	let (new_lp_total, _) = unsigned_div_rem(new_capital_total*_lp_total,_capital_total)
	let new_lp_issuance = new_lp_total - _lp_total

        # store all new data
        lp_total.write(new_lp_total)
        capital_total.write(new_capital_total)

        let (res) = lp_balances.read(user)
        lp_balances.write(user, res + new_lp_issuance)
        return (new_lp_issuance)
    end
end

# redeem LP tokens from user
@external
func withdraw_USDC_vs_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(with_LP : felt) -> (usd : felt):

    # check for existing lp tokens and capital
    let (_lp_total) = lp_total.read()
    let (_capital_total) = capital_total.read()

    # Verify that the amount is positive.
    with_attr error_message("Amount must be positive and below LP total available."):
        assert_nn_le(with_LP, _lp_total)
    end

    # Obtain the address of the account contract.
    let (user) = get_caller_address()
    let (lp_user) = lp_balances.read(user=user)

    with_attr error_message("Insufficent lp tokens to redeem."):
        assert_nn(lp_user-with_LP)
    end
	
    # calc new lp total
    let new_lp_total = _lp_total-with_LP
    
    # calc new capital total and capital to return
    let (new_capital_total, _) = unsigned_div_rem(new_lp_total*_capital_total,_lp_total)
    let new_capital_redeem = _capital_total - new_capital_total

    # store all new data
    lp_total.write(new_lp_total)
    capital_total.write(new_capital_total)

    let (res) = lp_balances.read(user)
    lp_balances.write(user, res - with_LP)
    return (new_capital_redeem)
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
