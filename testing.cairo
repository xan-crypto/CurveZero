# [StarkNet](https://starkware.co/product/starknet/) is a permissionless decentralized ZK-Rollup operating
# as an L2 network over Ethereum, where any dApp can achieve
# unlimited scale for its computation, without compromising
# Ethereum's composability and security.
#
# This is a simple StarkNet contract.
# Note that you won't be able to use the playground to compile and run it,
# but you can deploy it on the [StarkNet Planets Alpha network](https://medium.com/starkware/starknet-planets-alpha-on-ropsten-e7494929cb95)!
#
# 1. Click on "Deploy" to deploy the contract.
#    For more information on how to write Cairo contracts see the
#    ["Hello StarkNet" tutorial](https://cairo-lang.org/docs/hello_starknet).
# 2. Click on the contract address in the output pane to open
#    [Voyager](https://goerli.voyager.online/) - the StarkNet block explorer.
# 3. Wait for the page to load the information
#    (it may take a few minutes until a block is created).
# 4. In the "STATE" tab, you can call the "add()" transaction.

# The "%lang" directive declares this code as a StarkNet contract.
%lang starknet

# The "%builtins" directive declares the builtins used by the contract.
# For example, the "range_check" builtin is used to compare values.
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_le, assert_in_range, assert_nn
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import unsigned_div_rem

@storage_var
func staker_index(index:felt) -> (user : felt):
end

@view
func get_staker_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(index:felt) -> (user : felt):
    let (user) = staker_index.read(index=index)
    return (user)
end

func set_staker_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(index:felt,user : felt):
    staker_index.write(index,user)
    return ()
end

@storage_var
func staker_users(user:felt) -> (res : (felt,felt,felt)):
end

@view
func get_staker_users{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user:felt) -> (stake : felt, reward : felt, old_user:felt):
    let (res) = staker_users.read(user=user)
    return (res[0],res[1],res[2])
end

@external
func set_staker_users{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user:felt,stake_new : felt,):
    let (res) = staker_users.read(user=user)
    staker_users.write(user,(stake_new,res[1],1))
    return ()
end

@storage_var
func staker_total() -> (res : (felt,felt)):
end

@view
func get_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (stake_total : felt, index : felt):
    let (res) = staker_total.read()
    return (res[0],res[1])
end

@external
func set_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stake_total : felt, index : felt):
    let (res) = staker_total.read()
    staker_total.write((stake_total,index))
    return ()
end

@external
func czt_stake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt) -> (res:felt):
    
    alloc_locals
    # check stake is positve amount
    with_attr error_message("GT stake should be positive amount."):
        assert_nn(gt_token)
    end
    let (user) = get_caller_address()
    let (stake,reward,old_user) = get_staker_users(user)
    let (stake_total,index) = get_staker_total()
    
    set_staker_users(user,stake+gt_token)    
    if old_user == 1:
        set_staker_total(stake_total+gt_token,index)
        return(1)
    else:
        set_staker_total(stake_total+gt_token,index+1)
        set_staker_index(index,user)
        return(1)
    end
end

@external
func czt_unstake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt) -> (res:felt):
    
    alloc_locals
    # check stake is positve amount
    with_attr error_message("GT stake should be positive amount."):
        assert_nn(gt_token)
    end
    let (user) = get_caller_address()
    let (stake,reward,old_user) = get_staker_users(user)
    let (stake_total,index) = get_staker_total()
    
    # check stake is positve amount
    with_attr error_message("GT stake should be positive amount."):
        assert_nn(stake-gt_token)
    end
    
    set_staker_users(user,stake-gt_token)    
    set_staker_total(stake_total-gt_token,index)
    return(1)
end

@external
func distribute{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(reward_total : felt) -> (res:felt):
    
    alloc_locals
    # check stake is positve amount
    with_attr error_message("reward must be postive."):
        assert_nn(reward_total)
    end

    let (stake_total,index) = get_staker_total()
    run_distribution(stake_total,reward_total,index)

    return(1)
end

func run_distribution{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stake_total:felt,reward_total : felt, index : felt):
    alloc_locals
    if index == 0:
        return()
    end

    run_distribution(stake_total,reward_total,index-1)
    
    let (user) = get_staker_index(index-1)
    let (stake,reward,old_user) = get_staker_users(user)
    let (temp1,_) = unsigned_div_rem(stake,stake_total)
    tempvar temp2 = temp1*reward_total
    tempvar reward_new = temp2+reward
    staker_users.write(user,(stake,reward_new,1))
    return ()
end




