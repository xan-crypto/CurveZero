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
    let (paused) = Controller.get_paused(_controller_addy)
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
func lp_balances(user : felt) -> (res : (felt,felt)):
end

# returns the balance of the given user
@view
func get_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_user : felt, lockup: felt):
    let (res) = lp_balances.read(user=user)
    return (res[0],res[1])
end

# set the balance of the given user
@external
func set_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, amount : felt, lockup : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.get_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    lp_balances.write(user,(amount,lockup))
    return ()
end

##################################################################
# cz state
@storage_var
func cz_state() -> (res : (felt, felt, felt, felt)):
end

# returns the cz state
@view
func get_cz_state{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        lp_total : felt, capital_total : felt, loan_total : felt, insolvency_shortfall : felt):
    let (res) = cz_state.read()
    return (res[0],res[1],res[2],res[3])
end

# set the lp total
@external
func set_lp_capital_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_amount : felt, capital_amount : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.get_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    # read old cz state
    let (lp_total,capital_total,loan_total,insolvency_shortfall) = cz_state.read()
    cz_state.write(lp_amount,capital_amount,loan_total,insolvency_shortfall)
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
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_locked : felt, cz_locked : felt, status : felt):
    let (res) = pp_status.read(user=user)
    return (res[0],res[1],res[2])
end

# promote / demote pp
@external
func set_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        user : felt, lp_user : felt, lp_amount : felt, cz_amount : felt, lockup : felt, promote : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_pp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # check if paused
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.get_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end

    if promote == 1:
        # promote user to pp and lock lp and cz tokens
        # reduce lp balance of user
        lp_balances.write(user, (lp_user - lp_amount, lockup))
        # update the pp status
        pp_status.write(user, (lp_amount, cz_amount, 1))
    else:
        # demote user from pp and return lp and cz tokens
        # reduce lp balance of user
        lp_balances.write(user, (lp_user + lp_amount, lockup))
        # update the pp status
        pp_status.write(user, (0, 0, 0))    
    end    
    return ()
end

##################################################################
# functions to create loans, repay laons and refinance loans
# the CB loans by user
@storage_var
func cb_loan(user : felt) -> (loan : (felt, felt, felt, felt, felt, felt)):
end

# returns the CB loan of the given user
@view
func get_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (has_loan : felt, amount : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt):
    let (res) = cb_loan.read(user=user)
    return (res[0], res[1], res[2], res[3], res[4], res[5])
end

# set loan terms
@external
func set_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, has_loan : felt, amount : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, refinance : felt):
    # check authorised caller
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_cb_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    # new loans not allowed when system paused, refinancing loans still allowed
    if refinance != 1:
        # check if paused
        let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
        let (paused) = Controller.get_paused(_controller_addy)
        with_attr error_message("System is paused."):
            assert paused = 0
        end
    end
    get_cb_loan.write(user,(has_loan,amount,collateral,start_ts,end_ts,rate))
    return ()
end
