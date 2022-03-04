# controller can only pause and unpause, slash PP and GT and initiate a payout from IF to fund a shortfall
# controller will also be able to update some of the settings, controller key should be given to community when project matures
# when launch on mainnet ensure that controller is multisig

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn
from Functions.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add
from InterfaceAll import TrustedAddy, Settings, CZCore

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
# useful functions
func is_deployer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (deployer) = deployer_addy.read()
    with_attr error_message("Only deployer has access."):
        assert caller = deployer
    end
    return()
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
    is_deployer()
    trusted_addy.write(addy)
    return ()
end

##################################################################
# controller functions
# paused = 1 unpaused = 0
@storage_var
func paused() -> (res : felt):
end

# return paused = 1 unpaused = 0
@view
func get_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res) = paused.read()
    return (res)
end

# pause (pause new loans, refin/repay allowed, pause LP PP new/redeem, pause GT stake/unstake)
@external
func set_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    is_deployer()
    paused.write(1)
    return ()
end

# unpause
@external
func set_unpaused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    is_deployer()
    paused.write(0)
    return ()
end

# set new token requirement to become PP
@external
func set_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_require : felt, cz_require : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_pp_token_requirement(settings_addy,lp_require=lp_require,cz_require=cz_require)
    return ()
end

# set lock up period
@external
func set_lockup_period{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lockup : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_lockup_period(settings_addy,lockup =lockup)
    return ()
end

# set origination fee and split
@external
func set_origination_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt, pp_split : felt, if_split : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_origination_fee(settings_addy,fee=fee,pp_split=pp_split,if_split=if_split)
    return ()
end

# set accrued interest splits
@external
func set_accrued_interest_split{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_split : felt, if_split : felt, gt_split : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_accrued_interest_split(settings_addy,lp_split=lp_split,if_split=if_split,gt_split=gt_split)
    return ()
end

# set min and max loan sizes
@external
func set_min_max_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_loan : felt, max_loan : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_min_max_loan(settings_addy,min_loan=min_loan,max_loan=max_loan)
    return ()
end

# set level below which we make loans and above which we stop loans
@external
func set_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stop : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_utilization(settings_addy,stop=stop)
    return ()
end

# set min PP required for acceptable pricing request
@external
func set_min_pp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_pp : felt):
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    Settings.set_min_pp_accepted(settings_addy,min_pp=min_pp)
    return ()
end

# distribute rewards from total pot to individual users unclaimed rewards 
@external
func distribute_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res:felt):
    alloc_locals
    is_deployer()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)    
    # check total stake is positve amount
    with_attr error_message("Reward total must be postive."):
        assert_nn(reward_total)
    end
    let (stake_total,index) = CZCore.get_staker_total(czcore_addy)
    run_distribution(czcore_addy,stake_total,reward_total,index)
    # set CZCore reward_total to 0
    CZCore.set_reward_total(czcore_addy)
    return (1)
end

# send out user unclaimed rewards
func run_distribution{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(czcore_addy : felt, stake_total : felt, reward_total : felt, index : felt):
    alloc_locals
    if index == 0:
        return()
    end
    run_distribution(czcore_addy,stake_total,reward_total,index-1)
    let (user) = CZCore.get_staker_index(czcore_addy, index-1)
    let (stake, reward, old_user) = CZCore.get_staker_details(czcore_addy, user)
    let (temp1) = Math64x61_mul(reward_total, stake)
    let (temp2) = Math64x61_div(temp1,stake_total)
    let (reward_new) = Math64x61_add(temp2, reward)
    CZCore.set_staker_details(user,stake,reward_new,1)
    return ()
end
