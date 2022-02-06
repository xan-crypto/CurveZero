# LP contract

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

    # Obtain the address of the account contract & czcore
    let (user) = get_caller_address()
    let (_czcore_addy) = czcore_addy.read()
	
    # check for existing lp tokens and capital
    let (_lp_total) = CZCore.get_lp_total(_czcore_addy)
    let (_capital_total) = CZCore.get_capital_total(_czcore_addy)
    # calc new total capital
    let new_capital_total = _capital_total + depo_USD

    # calc new lp total and new lp issuance
    if _lp_total == 0:
        let new_lp_total = depo_USD
        let new_lp_issuance = depo_USD

        # store all new data
        CZCore.set_lp_total(_czcore_addy,new_lp_total)
        CZCore.set_capital_total(_czcore_addy,new_capital_total)

        let (res) = CZCore.get_lp_balance(_czcore_addy,user)
        CZCore.set_lp_balance(_czcore_addy,user, res + new_lp_issuance)
        return (new_lp_issuance)
    else:	
	let (new_lp_total, _) = unsigned_div_rem(new_capital_total*_lp_total,_capital_total)
	let new_lp_issuance = new_lp_total - _lp_total

        # store all new data
        CZCore.set_lp_total(_czcore_addy,new_lp_total)
        CZCore.set_capital_total(_czcore_addy,new_capital_total)

        let (res) = CZCore.get_lp_balance(_czcore_addy,user)
        CZCore.set_lp_balance(_czcore_addy,user, res + new_lp_issuance)
        return (new_lp_issuance)
    end
end

# redeem LP tokens from user
@external
func withdraw_USDC_vs_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(with_LP : felt) -> (usd : felt):

    # Obtain the address of the czcore contract
    let (_czcore_addy) = czcore_addy.read()

    # check for existing lp tokens and capital
    let (_lp_total) = CZCore.get_lp_total(_czcore_addy)
    let (_capital_total) = CZCore.get_capital_total(_czcore_addy)

    # Verify that the amount is positive.
    with_attr error_message("Amount must be positive and below LP total available."):
        assert_nn_le(with_LP, _lp_total)
    end

    # Obtain the address of the account contract.
    let (user) = get_caller_address()
    let (lp_user) = CZCore.get_lp_balance(_czcore_addy,user)

    with_attr error_message("Insufficent lp tokens to redeem."):
        assert_nn(lp_user-with_LP)
    end
	
    # calc new lp total
    let new_lp_total = _lp_total-with_LP
    
    # calc new capital total and capital to return
    let (new_capital_total, _) = unsigned_div_rem(new_lp_total*_capital_total,_lp_total)
    let new_capital_redeem = _capital_total - new_capital_total

    # store all new data
    CZCore.set_lp_total(_czcore_addy,new_lp_total)
    CZCore.set_capital_total(_czcore_addy,new_capital_total)

    let (res) = CZCore.get_lp_balance(_czcore_addy,user)
    CZCore.set_lp_balance(_czcore_addy,user, res - with_LP)
    return (new_capital_redeem)
end
