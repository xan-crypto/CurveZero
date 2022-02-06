# LP contract

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address

# addy of the CZCore contract
@storage_var
func czcore_addy() -> (addy : felt):
end

# set the CZCore contract addy
@external
func set_czcore_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addy : felt):
    czcore_addy.write(addy)
    return ()
end

# interface to trusted addys contract
@contract_interface
namespace CZCore:
    func get_lp_balance(user : felt) -> (res : felt):
    end
    func set_lp_balance(user : felt, amount : felt):
    end
    func get_lp_total() -> (res : felt):
    end
    func set_lp_total(amount : felt):
    end
    func get_capital_total() -> (res : felt):
    end
    func set_capital_total(amount : felt):
    end
    func get_loan_total() -> (res : felt):
    end
    func set_loan_total(amount : felt):
    end
    func get_insolvency_shortfall() -> (res : felt):
    end
    func set_insolvency_shortfall(amount : felt):
    end
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
