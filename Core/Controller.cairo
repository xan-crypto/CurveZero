####################################################################################
# @title Controller contract
# @dev all numbers passed into contract must be Math10xx8 type
# the controller will be a multisig wallet which will eventually be passed to the community
# the Controller contract can
# - get the owner addy
# - get/set the TrustedAddy contract address where all contract addys are stored
# - pause and unpause the protocol, this is required to prevent LP/PP/GT from removing liquidity/stake 
# in the case of a liquidity event / anomalous loan, also prevents the creation of new loans 
# - distribute rewards from CZCore to stakers, they can then claim that using the GovenanceToken contract
# - slash GT holders if liquidity gap, move funds to insurance fund 
# - do a system check to compare USDC asset/liabilities to USDC balance in the ERC20 contract
# This contract addy will be stored in the TrustedAddy contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn, assert_le
from starkware.cairo.common.math_cmp import is_in_range
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_add, Math10xx8_sub, Math10xx8_one, Math10xx8_fromUint256, Math10xx8_convert_to
from InterfaceAll import TrustedAddy, Settings, CZCore, Erc20
from Functions.Checks import check_is_owner, check_user_balance, get_user_balance

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
####################################################################################
@storage_var
func owner_addy() -> (addy : felt):
end

@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(owner : felt):
    owner_addy.write(owner)
    return ()
end

@view
func get_owner_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = owner_addy.read()
    return (addy)
end

####################################################################################
# @dev storage for the trusted addy contract
# the TrustedAddy contract stores all the contract addys
####################################################################################
@storage_var
func trusted_addy() -> (addy : felt):
end

@view
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = trusted_addy.read()
    return (addy)
end

@external
func set_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    trusted_addy.write(addy)
    return ()
end

####################################################################################
# @dev emit GT slash event for reporting / dashboard to monitor system
####################################################################################
@event
func event_gt_slash(slash_percentage : felt, stake_total : felt, new_stake_total : felt, index : felt):
end

####################################################################################
# @dev function to pause and unpause the protocol paused = 1 unpaused = 0
####################################################################################
@storage_var
func paused() -> (res : felt):
end

####################################################################################
# @dev get current state of protocol
# @return paused = 1 unpaused = 0
####################################################################################
@view
func get_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = paused.read()
    return (res)
end

####################################################################################
# @dev set paused / unpaused
####################################################################################
@external
func set_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    paused.write(1)
    return ()
end
@external
func set_unpaused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    paused.write(0)
    return ()
end

####################################################################################
# @dev distribute rewards from total pot to individual users unclaimed rewards 
# this function gets the total rewards from CZCore state and then distributes it via recursive function call
# we use the user stake vs total stake ratio to distribute rewards
# unclaimed user rewards are not affected
####################################################################################
@external
func distribute_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)    
    let (stake_total, index) = CZCore.get_staker_total(czcore_addy)
    run_distribution(czcore_addy, stake_total, reward_total, index)
    # @dev set CZCore reward_total to 0
    CZCore.set_cz_state(czcore_addy, lp_total, capital_total, loan_total, insolvency_total, 0)
    return ()
end

####################################################################################
# @dev send out user unclaimed rewards
# @param 
# - CZCore addy for getting user stake/unclaimed data
# - total stake for calculating reward ratio
# - reward total being distributed
# - index / count of number of stakers
####################################################################################
func run_distribution{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(czcore_addy : felt, stake_total : felt, reward_total : felt, index : felt):
    alloc_locals
    if index == 0:
        return()
    end
    run_distribution(czcore_addy, stake_total, reward_total, index-1)
    let (user) = CZCore.get_staker_index(czcore_addy, index-1)
    let (stake, unclaimed, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (staking_ratio) = Math10xx8_div(stake, stake_total)
    let (reward) = Math10xx8_mul(reward_total, staking_ratio)
    let (reward_new) = Math10xx8_add(reward, unclaimed)
    CZCore.set_staker_details(czcore_addy, user, stake, reward_new)
    return ()
end

####################################################################################
# @dev slash GTs and send the CZT totals to the owner
# AMM space on starknet is not mature enough to automate this yet
# the tokens will be sent to the owner addy which will be a multisig and from there converted to USDC and sent to the insurance fund
# @param 
# - GT slash percentage
####################################################################################
@external
func slash_gt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(slash_percentage : felt):
    alloc_locals
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (one) = Math10xx8_one()
    let (test_range) = is_in_range(slash_percentage, 0, one)
    with_attr error_message("Slash perecent not in required range."):
        assert test_range = 1
    end
    
    # @dev remain = 1 - slash, ratio down all users and total
    let (remain) = Math10xx8_sub(one, slash_percentage)
    let (stake_total, index) = CZCore.get_staker_total(czcore_addy)
    let (new_stake_total) = Math10xx8_mul(stake_total, remain)
    let (stake_slash) = Math10xx8_mul(stake_total, slash_percentage)
    CZCore.set_staker_total(czcore_addy, new_stake_total, index)
    
    # @dev check that czcore has eno CZT tokens and transfer
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    CZCore.erc20_transfer(czcore_addy, czt_addy, owner, stake_slash)
    run_slash(czcore_addy, remain, index)
    # @dev emit event
    event_gt_slash.emit(slash_percentage, stake_total, new_stake_total, index)  
    return()
end

####################################################################################
# @dev slashing each individual user
# @param 
# - CZCore addy for getting user stake/unclaimed data
# - 1 - slashing percentage
# - index / count of number of stakers
####################################################################################
func run_slash{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(czcore_addy : felt, remain : felt, index : felt):
    alloc_locals
    if index == 0:
        return()
    end
    run_slash(czcore_addy, remain, index-1)
    let (user) = CZCore.get_staker_index(czcore_addy, index-1)
    let (stake, unclaimed, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (new_stake) = Math10xx8_mul(stake, remain)
    CZCore.set_staker_details(czcore_addy, user, new_stake, unclaimed)
    return ()
end

####################################################################################
# @dev system check, check if USDC balance sufficient for all liabilities
# this function sums all the assets/liabilities in USDC and compare to the USDC balance on the ERC20 contract
# @return
# - current assets (loans, accrued interest, usd balance)
# - current liabilities (capital, reward, reward_unclaimed)
####################################################################################
@view
func system_check{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (loan_total : felt, accrued_interest_total : felt, usd_bal_total : felt, capital_total : felt, insolvency_total : felt, reward_total : felt, unclaimed_reward_total):
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)   
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (stake_total, index) = CZCore.get_staker_total(czcore_addy)
    
    # @dev get the total unclaimed rewards by all users    
    let (unclaimed_reward_total) = sum_unclaimed_rewards(czcore_addy, index)
    # @dev get USDC balance of for czcore 
    let (usd_bal_total) = get_user_balance(usdc_addy, czcore_addy)
    return(loan_total, accrued_interest_total, usd_bal_total, capital_total, insolvency_total, reward_total, unclaimed_reward_total)
end

####################################################################################
# @dev sums all user unclaimed rewards
# @param 
# - CZCore addy for getting user stake/unclaimed data
# - index / count of number of stakers
####################################################################################
func sum_unclaimed_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(czcore_addy : felt, index : felt) -> (sum : felt):
    alloc_locals
    if index == 0:
        return(0)
    end
    let (sum) = sum_unclaimed_rewards(czcore_addy, index-1)
    let (user) = CZCore.get_staker_index(czcore_addy, index-1)
    let (stake, unclaimed, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (new_sum) = Math10xx8_add(sum, unclaimed)
    return (new_sum)
end
