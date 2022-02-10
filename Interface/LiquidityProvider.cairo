# LP contract

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import (Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check)

##################################################################
# needed so that deployer can point LP contract to CZCore
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
# CZCore addy and interface, only deployer can point LP contract to CZCore
# addy of the CZCore contract
@storage_var
func czcore_addy() -> (addy : felt):
end

# get the CZCore contract addy
@view
func get_czcore_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = czcore_addy.read()
    return (addy)
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

# interface to CZCore contract
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
    func erc20_transferFrom(sender: felt, recipient: felt, amount: Uint256):
    end
end

##################################################################
# need to emit LP events so that we can do reporting / dashboard to monitor system
# events keeping tracks of what happened
@event
func lp_token_change(addy : felt, lp_change : felt, capital_change : felt):
end

##################################################################
# LP contract functions
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

    # check for existing lp tokens and capital from czcore
    let (_lp_total) = CZCore.get_lp_total(_czcore_addy)
    let (_capital_total) = CZCore.get_capital_total(_czcore_addy)
    # calc new total capital
    let new_capital_total = _capital_total + depo_USD

    # calc new lp total and new lp issuance
    if _lp_total == 0:
        let new_lp_total = depo_USD
        let new_lp_issuance = depo_USD

        # transfer the actual USDC tokens to CZCore reserves
        CZCore.erc20_transferFrom(_czcore_addy, user, _czcore_addy, depo_USD)

        # store all new data
        CZCore.set_lp_total(_czcore_addy,new_lp_total)
        CZCore.set_capital_total(_czcore_addy,new_capital_total)
        
	# mint the lp token
	let (res) = CZCore.get_lp_balance(_czcore_addy,user)
        CZCore.set_lp_balance(_czcore_addy,user, res + new_lp_issuance)

        # event
        lp_token_change.emit(addy=user,lp_change=new_lp_issuance,capital_change=depo_USD)
        return (new_lp_issuance)
    else:	
        let (new_lp_total, _) = unsigned_div_rem(new_capital_total*_lp_total,_capital_total)
	let new_lp_issuance = new_lp_total - _lp_total

        # transfer the actual USDC tokens to CZCore reserves
        CZCore.erc20_transferFrom(_czcore_addy, user, _czcore_addy, depo_USD)

        # store all new data
        CZCore.set_lp_total(_czcore_addy,new_lp_total)
        CZCore.set_capital_total(_czcore_addy,new_capital_total)
	
	# mint the lp token
        let (res) = CZCore.get_lp_balance(_czcore_addy,user)
        CZCore.set_lp_balance(_czcore_addy,user, res + new_lp_issuance)

        # event
        lp_token_change.emit(addy=user,lp_change=new_lp_issuance,capital_change=depo_USD)
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

    # verify that the amount is positive.
    with_attr error_message("Amount must be positive and below LP total available."):
        assert_nn_le(with_LP, _lp_total)
    end

    # obtain the address of the account contract and user lp balance.
    let (user) = get_caller_address()
    let (lp_user) = CZCore.get_lp_balance(_czcore_addy,user)

    # verify user has sufficient LP tokens to redeem
    with_attr error_message("Insufficent lp tokens to redeem."):
        assert_nn(lp_user-with_LP)
    end
	
    # calc new lp total
    let new_lp_total = _lp_total-with_LP
    
    # calc new capital total and capital to return
    let (new_capital_total, _) = unsigned_div_rem(new_lp_total*_capital_total,_lp_total)
    let new_capital_redeem = _capital_total - new_capital_total

    # transfer the actual USDC tokens from CZCore reserves
    CZCore.erc20_transferFrom(_czcore_addy, _czcore_addy, user, new_capital_redeem)

    # store all new data
    CZCore.set_lp_total(_czcore_addy,new_lp_total)
    CZCore.set_capital_total(_czcore_addy,new_capital_total)
    
    # burn lp tokens
    let (res) = CZCore.get_lp_balance(_czcore_addy,user)
    CZCore.set_lp_balance(_czcore_addy,user, res - with_LP)
    
    # event
    lp_token_change.emit(addy=user,lp_change=-with_LP,capital_change=-new_capital_redeem)
    return (new_capital_redeem)
end

# whats my LP tokens worth
@view
func lp_token_worth{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (usd : felt):

    # Obtain the address of the czcore contract
    let (_czcore_addy) = czcore_addy.read()

    # check total lp tokens and capital
    let (_lp_total) = CZCore.get_lp_total(_czcore_addy)
    let (_capital_total) = CZCore.get_capital_total(_czcore_addy)

    # Obtain the user lp tokens
    let (lp_user) = CZCore.get_lp_balance(_czcore_addy,user)

    # calc user capital to return
    if lp_user == 0:
    	return (0)
    else:
        let (capital_user, _) = unsigned_div_rem(lp_user*_capital_total,_lp_total)
	return (capital_user)
    end
end
