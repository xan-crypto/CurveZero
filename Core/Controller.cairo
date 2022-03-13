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
from starkware.cairo.common.math import assert_nn
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_add
from InterfaceAll import TrustedAddy, Settings, CZCore
from Functions.Checks import check_is_owner

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
    CZCore.set_staker_details(user,stake,reward_new,1)
    return ()
end
