####################################################################################
# @title GovenanceToken contract
# @dev all numbers passed into contract must be Math10xx8 type
# CZT (curvezero) native tokens are staked to provide insurance in the case of massive loan insolveny
# in such an event the staked CZT tokens can be slashed to bridge the liquidity gap
# stakers are rewarded 5% of the accrued interest on all loans for bearing this risk
# the reward split is in the Settings contract and can be amended by the controller
# rewards are accrued to CZCore at the time of loan repayment, these are held there pending distribution by controller
# the controller can call distribute that will update the reward mapping for users
# this can be done at random to prevent any gaming of the system, since not practical to distribute on each loan repayment
# Users can
# - stake CZT tokens to earn a portion of the accrued interest
# - unstake CZT tokens 
# - view rewards accrued so far
# - claim rewards
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math10xx8 import Math10xx8_sub, Math10xx8_add
from Functions.Checks import check_is_owner, check_user_balance, check_insurance_shortfall_ratio, check_gt_stake, check_gt_unstake

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
# this allows for upgradability of this contract
####################################################################################
@storage_var
func owner_addy() -> (addy : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
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
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
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
# @dev need to emit GT events so that we can do reporting / dashboard / monitor system
# TODO check that this reports correctly for negative / reductions
####################################################################################
@event
func gt_stake_unstake(addy : felt, stake_current : felt):
end

@event
func gt_claim(addy : felt, reward : felt):
end

####################################################################################
# @dev stake CZT tokens to earn proportional rewards, 5% of accrued interest initially
# @param input is the amount of CZT tokens to stake
####################################################################################
@external
func czt_stake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt):    
    alloc_locals
    # @dev check stake is positve amount
    check_gt_stake(gt_token)
    
    # @dev check user have the coins to stake
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (user) = get_caller_address()
    check_user_balance(czt_addy, user, gt_token)
    
    # @dev check insurance shortfall ratio acceptable
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_insurance_shortfall_ratio(settings_addy, capital_total, insolvency_total)

    # @dev get user and total staking details
    let (gt_user, reward, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (gt_total, index) = CZCore.get_staker_total(czcore_addy)

    # @dev transfer tokens
    CZCore.erc20_transferFrom(czcore_addy, czt_addy, user, czcore_addy, gt_token)   
    # @dev update user and aggregate
    let (gt_user_new) = Math10xx8_add(gt_user, gt_token)
    let (gt_total_new) = Math10xx8_add(gt_total, gt_token)
    CZCore.set_staker_details(czcore_addy, user, gt_user_new, reward)    
    if old_user == 1:
        CZCore.set_staker_total(czcore_addy, gt_total_new, index)
        # @dev emit event
        gt_stake_unstake.emit(user, gt_user_new)
        return()
    else:
        CZCore.set_staker_total(czcore_addy, gt_total_new, index + 1)
        CZCore.set_staker_index(czcore_addy, index, user)
        # @dev emit event
        gt_stake_unstake.emit(user, gt_user_new)
        return()
    end
end

####################################################################################
# @dev unstake CZT tokens, doesnt affect existing unclaimed rewards
# @param input is the amount of CZT tokens to unstake
####################################################################################
@external
func czt_unstake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt):
    alloc_locals
    # @dev check unstake is positve amount
    check_gt_stake(gt_token)
    
    # @dev check insurance shortfall ratio acceptable
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_insurance_shortfall_ratio(settings_addy, capital_total, insolvency_total)
    
    # @dev get user and total staking details
    let (gt_user, reward, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (gt_total, index) = CZCore.get_staker_total(czcore_addy)
    
    # @dev check user have the coins to unstake
    check_gt_unstake(gt_token, gt_user)
    
    # @dev update user and aggregate
    let (gt_user_new) = Math10xx8_sub(gt_user, gt_token)
    let (gt_total_new) = Math10xx8_sub(gt_total, gt_token)

    # @dev transfer tokens, update user and aggregate
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    CZCore.set_staker_details(czcore_addy, user, gt_user_new, reward)   
    CZCore.set_staker_total(czcore_addy, gt_total_new, index)
    CZCore.erc20_transfer(czcore_addy, czt_addy, user, gt_token)            
    # @dev emit event
    gt_stake_unstake.emit(user, gt_user_new)
    return()
end

####################################################################################
# @dev view rewards accrued to a staker
# @param input is the user addy
# @return 
# - the CZT tokens currently staked by user
# - the reward accrued to user thats currently claimable
####################################################################################
@view
func view_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (gt_user : felt, reward : felt):
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    # @dev get current user stake
    let (gt_user, reward, old_user) = CZCore.get_staker_details(czcore_addy, user)
    return(gt_user, reward)
end

####################################################################################
# @dev claim rewards in portion to CZT staked
####################################################################################
@external
func claim_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    # @dev get current user stake
    let (gt_user, reward, old_user) = CZCore.get_staker_details(czcore_addy,user)
    # @dev transfer tokens
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    # @dev update user rewards
    CZCore.set_staker_details(czcore_addy, user, gt_user, 0)   
    # @dev transfer tokens
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, reward)   
    # @dev emit event
    gt_claim.emit(user, reward)
    return()
end