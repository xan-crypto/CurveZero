# GT contract
# all numbers passed into contract must be Math64x61 type

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_le, assert_in_range, assert_nn
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Math.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add, Math64x61_convert_from, Math64x61_ts
from Functions.Checks import check_is_owner

##################################################################
# addy of the owner
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

##################################################################
# trusted addy where contract addys are stored, only owner can change this
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

##################################################################
# need to emit GT events so that we can do reporting / dashboard to monitor system
# dont need to emit totals since can do that with history of changes
@event
func gt_stake_unstake(addy : felt, stake : felt):
end

@event
func gt_claim(addy : felt, reward : felt):
end

##################################################################
# GT contract functions
# stake GT tokens to earn proportional rewards 2% of accrued interest initially
@external
func czt_stake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt) -> (res:felt):
    
    alloc_locals
    # check stake is positve amount
    with_attr error_message("GT stake should be positive amount."):
        assert_nn(gt_token)
    end
    
    # check user have the coins to stake
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (user) = get_caller_address()
    let (czt_user) = Erc20.ERC20_balanceOf(czt_addy, user)
    let (czt_decimals) = Erc20.ERC20_decimals(czt_addy)
    let (gt_token_erc) = Math64x61_convert_from(gt_token, czt_decimals)
    with_attr error_message("User does not have sufficient funds."):
        assert_le(gt_token_erc, czt_user)
    end
    
    # get user and total staking details
    let (gt_user, reward, old_user) = CZCore.get_staker_users(czcore_addy,user)
    let (gt_total, index) = CZCore.get_staker_total(czcore_addy)

    # transfer tokens
    CZCore.erc20_transferFrom(czcore_addy, czt_addy, user, czcore_addy, gt_token_erc)   
    # update user and aggregate
    let (gt_user_new) = Math64x61_add(gt_user, gt_token)
    let (gt_total_new) = Math64x61_add(gt_total, gt_token)
    CZCore.set_staker_users(user, gt_user_new, reward)    
    if old_user == 1:
        CZCore.set_staker_total(gt_total_new, index)
        # event
        gt_stake_unstake.emit(addy=user,stake=gt_token)
        return(1)
    else:
        CZCore.set_staker_total(gt_total_new, index + 1)
        CZCore.set_staker_index(index, user)
        # event
        gt_stake_unstake.emit(addy=user,stake=gt_token)
        return(1)
    end
end

# unstake GT tokens, doesnt affect existing unclaimed rewards
@external
func czt_unstake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt) -> (res:felt):
    
    alloc_locals
    # check unstake is positve amount
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    with_attr error_message("GT unstake should be positive amount."):
        assert_nn(gt_token)
    end
    
    # get user and total staking details
    let (gt_user, reward, old_user) = CZCore.get_staker_users(czcore_addy,user)
    let (gt_total, index) = CZCore.get_staker_total(czcore_addy)
    
    # check user have the coins to unstake
    with_attr error_message("User does not have sufficient funds to unstake."):
        assert_le(gt_token, gt_user)
    end

    # update user and aggregate
    let (gt_user_new) = Math64x61_sub(gt_user, gt_token)
    let (gt_total_new) = Math64x61_sub(gt_total, gt_token)

    # transfer tokens
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_decimals) = Erc20.ERC20_decimals(czt_addy)
    let (gt_token_erc) = Math64x61_convert_from(gt_token, czt_decimals)
    CZCore.erc20_transfer(czcore_addy, czt_addy, user, gt_token_erc)            
    
    # update user and aggregate
    CZCore.set_staker_users(user, gt_user_new, reward)   
    CZCore.set_staker_total(gt_total_new, index)
    # event
    gt_stake_unstake.emit(addy=user,stake=-gt_token)
    return(1)
end

# claim rewards in portion to GT staked time
@external
func claim_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res:felt):

    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    
    # get current user staking time
    let (gt_user, reward, old_user) = CZCore.get_staker_users(czcore_addy,user)
    
    # transfer tokens
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (reward_erc) = Math64x61_convert_from(reward, usdc_decimals)
        
    # transfer tokens
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, reward_erc)            
    # update user rewards
    CZCore.set_staker_users(user, gt_user, 0)   
    
    # event
    gt_claim.emit(addy=user,reward=reward)
    return(1)
end
