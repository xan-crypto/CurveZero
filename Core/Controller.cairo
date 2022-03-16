####################################################################################
# @title Controller contract
# @dev all numbers passed into contract must be Math10xx8 type
# the controller will be a multisig wallet which will eventually be passed to the community
# the Controller contract can
# - get the owner addy
# - get/set the TrustedAddy contract address where all contract addys are stored
# - pause and unpause the protocol, this is required to prevent LP/PP/GT from removing liquidity/stake 
# in the case of a liquidity event / anomalous loan, also prevents the creation of new loans 
# - distribute rewards from CZCore to stakers, they can they claim that using the GovenanceToken contract
# - slash PP if anomalous behaviour detected, move funds to insurance fund
# - slash GT holders if liquidity gap, move funds to insurance fund 
# This contract addy will be stored in the TrustedAddy contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn, assert_le
from starkware.cairo.common.math_cmp import is_in_range
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_add, Math10xx8_sub, Math10xx8_one
from InterfaceAll import TrustedAddy, Settings, CZCore
from Functions.Checks import check_is_owner, check_user_balance

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
# @dev emit PP slash / GT slash event for reporting / dashboard to monitor system
####################################################################################
@event
func event_pp_slash(addy : felt, pp_status : felt, lp_slashed : felt, czt_slashed : felt):
end

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
    # @dev check total total is positve amount
    with_attr error_message("Reward total must be postive."):
        assert_nn(reward_total)
    end
    let (stake_total,index) = CZCore.get_staker_total(czcore_addy)
    run_distribution(czcore_addy,stake_total,reward_total,index)
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
    run_distribution(czcore_addy,stake_total,reward_total,index-1)
    let (user) = CZCore.get_staker_index(czcore_addy, index-1)
    let (stake, unclaimed, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (temp1) = Math10xx8_mul(reward_total, stake)
    let (temp2) = Math10xx8_div(temp1,stake_total)
    let (reward_new) = Math10xx8_add(temp2, unclaimed)
    CZCore.set_staker_details(czcore_addy, user, stake, reward_new)
    return ()
end

####################################################################################
# @dev slash pp which has been malcious 
# we use the pp slash percentage in settings
# lp tokens are burnt => value accrued to normal LPs that would have been affected by the malcious behaviour
# eg. 1000 LP tokens and 1000 USDC, malcious PP with 100 LP, we burn 50% say, so 950 LP and 1000 USDC, PP demoted and left with 50 lp only
# avg lp value 1 USDC (1000 USDC/1000), post burn 1.052 USDC (1000/950)
# so 900 lp @ 1 vs 900 lp @ 1.052 and 100 lp @ 1 vs 50 lp @ 1.052
# CZT token is taken by the contract owner, this is then swapped into USDC and added to the insurance fund
# reason we do this is that need flexible at the time, and dont want to write swap logic into contract, nor pick an AMM winner in advance
# will be possible to automate this step when clear AMM winner exists on starknet
# @param 
# - PP addy thats getting slashed
####################################################################################
@external
func slash_pp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt):
    alloc_locals
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    # @dev check if status 1 - has to be a valid pp
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    with_attr error_message("User is not an existing PP."):
        assert pp_status = 1
    end
    
    # @dev get slash percentage
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (slash) = Settings.get_pp_slash_percentage(settings_addy)    
    let (lp_slashed) = Math10xx8_mul(lp_locked, slash)
    let (czt_slashed) = Math10xx8_mul(czt_locked, slash)
    let (lp_remain) = Math10xx8_sub(lp_locked, lp_slashed)
    let (czt_remain) = Math10xx8_sub(czt_locked, czt_slashed)
    
    # @dev check that czcore has eno CZT tokens and transfer
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_remain_erc) = check_user_balance(czcore_addy, czt_addy, czt_remain)
    CZCore.erc20_transfer(czcore_addy, czt_addy, user, czt_remain_erc)
    let (czt_slashed_erc) = check_user_balance(czcore_addy, czt_addy, czt_slashed)
    CZCore.erc20_transfer(czcore_addy, czt_addy, owner, czt_slashed_erc)
    
    # @dev demote PP and burn lp
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    CZCore.set_pp_status(czcore_addy, user, lp_user, lp_remain, czt_remain, lockup, 0)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    with_attr error_message("Slash must be less or equal to LP total."):
        assert_le(lp_slashed, lp_total)
    end
    let (new_lp_total) = Math10xx8_sub(lp_total, lp_slashed)
    CZCore.set_cz_state(czcore_addy, new_lp_total, capital_total, loan_total, insolvency_total, reward_total)
    # @dev emit event
    event_pp_slash.emit(addy=user, pp_status=0, lp_slashed=lp_slashed, czt_slashed=czt_slashed)  
    return()
end

####################################################################################
# @dev slash GTs and send the CZT totals to the owner
# as per above with PP slashing the AMM space on starknet is not mature enough to automate this yet
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
    let (stake_slash_erc) = check_user_balance(czcore_addy, czt_addy, stake_slash)
    CZCore.erc20_transfer(czcore_addy, czt_addy, owner, stake_slash_erc)
    
    run_slash(czcore_addy, remain, index)
    # @dev emit event
    event_gt_slash.emit(slash_percentage=slash_percentage, stake_total=stake_total, new_stake_total=new_stake_total, index=index)  
    return()
end

####################################################################################
# @dev send out user unclaimed rewards
# @param 
# - CZCore addy for getting user stake/unclaimed data
# - total stake for calculating reward ratio
# - reward total being distributed
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
