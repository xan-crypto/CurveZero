# CZCore contract
# all interactions with reserves or state should flow through here

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import (Uint256)
from InterfaceAll import (TrustedAddy,Controller,Erc20)

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
# useful functions
func is_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.get_paused(_controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
end

func lp_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
end

func pp_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_pp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
end

func cb_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_cb_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
end

func ll_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_ll_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
end

func gt_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_gt_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
end

##################################################################
# this is a pass thru function to the ERC-20 token contract
@external
func erc20_transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, sender: felt, recipient: felt, amount: felt):
    lp_caller()
    is_paused()
    Erc20.ERC20_transferFrom(erc_addy,sender=sender,recipient=recipient,amount=amount)
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
    lp_caller()
    is_paused()
    lp_balances.write(user,(amount,lockup))
    return ()
end

##################################################################
# cz state
@storage_var
func cz_state() -> (res : (felt, felt, felt, felt, felt)):
end

# returns the cz state
@view
func get_cz_state{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        lp_total : felt, capital_total : felt, loan_total : felt, insolvency_total : felt, reward_total : felt):
    let (res) = cz_state.read()
    return (res[0],res[1],res[2],res[3],res[4])
end

# set the lp total
@external
func set_lp_capital_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_amount : felt, capital_amount : felt):
    lp_caller()
    is_paused()
    let (res) = cz_state.read()
    cz_state.write((lp_amount,capital_amount,res[2],res[3],res[4]))
    return ()
end

# set the loan total
@external
func set_captal_loan_reward_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(capital_amount : felt, loan_amount : felt, reward_amount : felt):
    cb_caller()
    is_paused()
    let (res) = cz_state.read()
    cz_state.write((res[0],capital_amount,loan_amount,res[3],reward_amount))
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
    pp_caller()
    is_paused()
    if promote == 1:
        # promote user to pp and lock lp and cz tokens
        lp_balances.write(user, (lp_user - lp_amount, lockup))
        pp_status.write(user, (lp_amount, cz_amount, 1))
    else:
        # demote user from pp and return lp and cz tokens
        lp_balances.write(user, (lp_user + lp_amount, lockup))
        pp_status.write(user, (0, 0, 0))    
    end    
    return ()
end

##################################################################
# functions to create loans, repay laons and refinance loans
# the CB loans by user
@storage_var
func cb_loan(user : felt) -> (res : (felt, felt, felt, felt, felt, felt)):
end

# returns the CB loan of the given user
@view
func get_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt):
    let (res) = cb_loan.read(user=user)
    return (res[0], res[1], res[2], res[3], res[4], res[5])
end

# set loan terms
@external
func set_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, refinance : felt):
    cb_caller()
    # new loans not allowed when system paused, refinancing loans still allowed
    if refinance != 1:
    	is_paused()
	cb_loan.write(user,(has_loan,notional,collateral,start_ts,end_ts,rate))
        return()
    else:
	cb_loan.write(user,(has_loan,notional,collateral,start_ts,end_ts,rate))
        return()
    end		
end

##################################################################
# functions to record user and total staking -> reward distribution triggered by controller
# index that maps index to unique users
@storage_var
func staker_index(index:felt) -> (user : felt):
end

# returns user which mapped to that index
@view
func get_staker_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(index : felt) -> (user : felt):
    let (user) = staker_index.read(index=index)
    return (user)
end

# sets index / user mapping
@external
func set_staker_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(index:felt,user : felt):
    gt_caller()
    is_paused()
    staker_index.write(index,user)
    return ()
end

# maps unique users to their stake, unclaimed rewards, old_user status
@storage_var
func staker_details(user:felt) -> (res : (felt,felt,felt)):
end

# returns stake, unclaimed rewards, old_user status
@view
func get_staker_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user:felt) -> (gt_token : felt, unclaimed_reward : felt, old_user:felt):
    let (res) = staker_details.read(user=user)
    return (res[0],res[1],res[2])
end

# sets stake, unclaimed rewards, old_user status
@external
func set_staker_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, gt_token : felt, unclaimed_reward : felt):
    gt_caller()
    is_paused()
    staker_details.write(user,(gt_token,unclaimed_reward,1))
    return ()
end

# total amount staked and index of unique stakers
@storage_var
func staker_total() -> (res : (felt,felt)):
end

# get total amount staked and index of unique stakers
@view
func get_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (stake_total : felt, index : felt):
    let (res) = staker_total.read()
    return (res[0],res[1])
end

# set total amount staked and index of unique stakers
@external
func set_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stake_total : felt, index : felt):
    gt_caller()
    is_paused()
    staker_total.write((stake_total,index))
    return ()
end
