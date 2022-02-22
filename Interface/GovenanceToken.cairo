# GT contract
# all numbers passed into contract must be Math64x61 type

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_le, assert_in_range, assert_nn
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Math.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add, Math64x61_convert_from, Math64x61_ts

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(deployer : felt):
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
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
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
# need to emit LP events so that we can do reporting / dashboard to monitor system
# dont need to emit total lp and total capital since can do that with history of changes
@event
func gt_stake_unstake(addy : felt, stake : felt):
end

@event
func gt_claim(addy : felt, reward : felt):
end

##################################################################
# GT contract functions
# stake GT tokens to earn staking time which aportions to rewards
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
    
    # get current user staking time
    let (gt_user, avg_time_user) = CZCore.get_staking_time_user(czcore_addy,user)
    # get aggregate staking time
    let (gt_total, avg_time_total) = CZCore.get_staking_time_total(czcore_addy)
    let (block_ts) = Math64x61_ts()
    
    # cal new user / total staking time
    let (new_gt_user, new_avg_time_user) = update_staking(gt_user, avg_time_user, gt_token, block_ts)
    let (new_gt_total, new_avg_time_total) = update_staking(gt_total, avg_time_total, gt_token, block_ts)    
       
    # transfer tokens
    CZCore.erc20_transferFrom(czcore_addy, czt_addy, user, czcore_addy, gt_token_erc)            
    # update user
    CZCore.set_staking_time_user(czcore_addy, user, new_gt_user, new_avg_time_user)
    # update aggregate
    CZCore.set_staking_time_total(czcore_addy, new_gt_total, new_avg_time_total)
    # event
    gt_stake_unstake.emit(addy=user,stake=gt_token)
    return(1)
end

# update staking function
func update_staking{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(old_gt:felt,old_time:felt,new_gt:felt,new_time:felt) -> (updated_gt:felt,updated_time:felt):
    alloc_locals
    if old_gt == 0:
        return(new_gt,new_time)
    else:
        let (temp1) = Math64x61_add(old_gt, new_gt)        
        if temp1 == 0: 
            return(0,0)
        else:
            let (temp2) = Math64x61_mul(old_gt, old_time)
            let (temp3) = Math64x61_mul(new_gt, new_time)
            let (temp4) = Math64x61_add(temp2, temp3)
            let (temp5) = Math64x61_div(temp4, temp1)
            return(temp1,temp5)    
        end
    end
end

# unstake GT tokens, call claim before if unstaking all
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
    
    # get current user staking time
    let (gt_user, avg_time_user) = CZCore.get_staking_time_user(czcore_addy,user)
    # get aggregate staking time
    let (gt_total, avg_time_total) = CZCore.get_staking_time_total(czcore_addy)
    let (block_ts) = Math64x61_ts()
    
    # check user have the coins to unstake
    with_attr error_message("User does not have sufficient funds to unstake."):
        assert_le(gt_token, gt_user)
    end

    # cal new user / total staking time
    let (new_gt_user, new_avg_time_user) = update_staking(gt_user, avg_time_user, -gt_token, block_ts)
    let (new_gt_total, new_avg_time_total) = update_staking(gt_total, avg_time_total, -gt_token, block_ts)   

    # if no more coins post unstake => call claim for user
    if new_gt_user == 0:
        claim_rewards()
        # check user have the coins to stake
        let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
        let (czt_decimals) = Erc20.ERC20_decimals(czt_addy)
        let (gt_token_erc) = Math64x61_convert_from(gt_token, czt_decimals)

        # transfer tokens
        CZCore.erc20_transferFrom(czcore_addy, czt_addy, czcore_addy, user, gt_token_erc)            
        # update user
        CZCore.set_staking_time_user(czcore_addy, user, new_gt_user, new_avg_time_user)
        # update aggregate
        CZCore.set_staking_time_total(czcore_addy, new_gt_total, new_avg_time_total)
        # event
        gt_stake_unstake.emit(addy=user,stake=-gt_token)
        return(1)
    else:
        # check user have the coins to stake
        let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
        let (czt_decimals) = Erc20.ERC20_decimals(czt_addy)
        let (gt_token_erc) = Math64x61_convert_from(gt_token, czt_decimals)

        # transfer tokens
        CZCore.erc20_transferFrom(czcore_addy, czt_addy, czcore_addy, user, gt_token_erc)            
        # update user
        CZCore.set_staking_time_user(czcore_addy, user, new_gt_user, new_avg_time_user)
        # update aggregate
        CZCore.set_staking_time_total(czcore_addy, new_gt_total, new_avg_time_total)
        # event
        gt_stake_unstake.emit(addy=user,stake=-gt_token)
        return(1)
    end
end

# claim rewards in portion to GT staked time
@external
func claim_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res:felt):

    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    
    # get current user staking time
    let (gt_user, avg_time_user) = CZCore.get_staking_time_user(czcore_addy,user)
    # get aggregate staking time
    let (gt_total, avg_time_total) = CZCore.get_staking_time_total(czcore_addy)
    let (block_ts) = Math64x61_ts()    
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)    
    
    # aportion reward for user
    let (temp1) = Math64x61_sub(block_ts,avg_time_user)
    let (temp2) = Math64x61_mul(gt_user,temp1)
    let (temp3) = Math64x61_sub(block_ts,avg_time_total)
    let (temp4) = Math64x61_mul(gt_total,temp3)
    let (temp5) = Math64x61_div(temp2,temp4)
    let (reward) = Math64x61_mul(temp5,reward_total)
    
    # transfer tokens
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (reward_erc) = Math64x61_convert_from(reward, usdc_decimals)
        
    # transfer tokens
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, czcore_addy, user, reward_erc)            
    # update reward_total
    let (new_reward_total) = Math64x61_sub(reward_total,reward)
    CZCore.set_reward_total(czcore_addy, new_reward_total)      
    
    # event
    gt_claim.emit(addy=user,reward=reward)
    return(1)
end
