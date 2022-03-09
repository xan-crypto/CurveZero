####################################################################################
# @title CZCore contract
# @dev all numbers passed into contract must be Math10xx8 type
# all interactions with reserves or state should flow through here
# the Interface contracts can
# - get the owner addy
# - get/set the TrustedAddy contract address where all contract addys are stored
# - transfer erc20 tokens from user to CZCore
# - transfer erc20 tokens to addy from CZCore
# - get/set a users LP tokens and lockup period
# - get/set cz state (lp total, capital total, loan total, insolvency total, reward total)
# - get/set PP status and lp and czt token locked
# - get/set a user loan
# - get/set index of stakers needed for distributions
# - get/set a users stake and unclaimed rewards
# - get/set the total stake and index/count of stakers
# This contract addy will be stored in the TrustedAddy contract
# This contract is the main contract of the CurveZero protocol
# most other contracts can be easily swapped out, this is not true of CZCore because of the total/user state and reserves stored
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import (Uint256)
from InterfaceAll import (TrustedAddy,Controller,Erc20)
from Functions.Math10xx8 import Math10xx8_toUint256 

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
####################################################################################
@storage_var
func owner_addy() -> (addy : felt):
end

@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(owner : felt):
    owner_addy.write(deployer)
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
    let (caller) = get_caller_address()
    let (deployer) = deployer_addy.read()
    with_attr error_message("Only deployer can change the Trusted addy."):
        assert caller = deployer
    end
    trusted_addy.write(addy)
    return ()
end

####################################################################################
# @dev useful 
# below functions are all specific to CZCore so no need to move to Checks contract
# functions below include
# - check if system is currently paused
# - check if caller is the LiquidityProvider contract
# - check if caller is the PricingProvider contract
# - check if caller is the CapitalBorrower contract
# - check if caller is the LoanLiquidator contract
# - check if caller is the GovenanceToken contract
# - check if caller is the InsuranceFund contract
# - check if caller is the Controller contract
# - check if caller is authorised i.e. either LP, PP, CB, LL, GT or IF contract
####################################################################################
func is_paused{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (_trusted_addy) = trusted_addy.read()
    let (controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    let (paused) = Controller.get_paused(controller_addy)
    with_attr error_message("System is paused."):
        assert paused = 0
    end
    return()
end

func lp_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_lp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func pp_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_pp_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func cb_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_cb_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func ll_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_ll_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func gt_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_gt_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func if_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_if_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func controller_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (authorised_caller) = TrustedAddy.get_controller_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = authorised_caller
    end
    return()
end

func authorised_callers{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (lp_addy) = TrustedAddy.get_lp_addy(_trusted_addy)
    let (pp_addy) = TrustedAddy.get_pp_addy(_trusted_addy)
    let (cb_addy) = TrustedAddy.get_cb_addy(_trusted_addy)
    let (ll_addy) = TrustedAddy.get_ll_addy(_trusted_addy)
    let (gt_addy) = TrustedAddy.get_gt_addy(_trusted_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    if caller == lp_addy:
    	return()
    end
    if caller == pp_addy:
    	return()
    end    
    if caller == cb_addy:
    	return()
    end
    if caller == ll_addy:
    	return()
    end
    if caller == gt_addy:
    	return()
    end
    if caller == if_addy:
    	return()
    end
    with_attr error_message("Not in list of authorised callers."):
        assert 0 = 1
    end
    return()
end

####################################################################################
# @dev this is a pass thru function to the generic ERC-20 token contract
# - this is generally used to transfer user collateral into CZCore or for loan repayment for example
# @param input is
# - the erc20 contract address
# - the sender of the funds (sender needs to have sufficient allowance set for the recipient)
# - the recipient of the funds 
# - the amount in erc20 decimal format converted prior to being sent here
#################################################################################### 
@external
func erc20_transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, sender: felt, recipient: felt, amount: felt):
    authorised_callers()
    is_paused()
    let (amount_unit) = Math10xx8_toUint256(amount)
    Erc20.ERC20_transferFrom(erc_addy,sender=sender,recipient=recipient,amount=amount_unit)
    return ()
end

####################################################################################
# @dev this is a pass thru function to the generic ERC-20 token contract
# this is generally used to send tokens form CZCore to other addy e.g. pay a PP the origination fee
# @param input is
# - the erc20 contract address
# - the recipient of the funds 
# - the amount in erc20 decimal format converted prior to being sent here
####################################################################################
@external
func erc20_transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, recipient: felt, amount: felt):
    authorised_callers()
    is_paused()
    let (amount_unit) = Math10xx8_toUint256(amount)
    Erc20.ERC20_transfer(erc_addy,recipient=recipient,amount=amount_unit)
    return ()
end 

####################################################################################
# @dev the LP token balances by user
####################################################################################
@storage_var
func lp_balances(user : felt) -> (res : (felt,felt)):
end

####################################################################################
# @dev functions to get lp tokens by user
# @param input is
# - the user addy
# @return 
# - the users lp tokens and current lockup
####################################################################################
@view
func get_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_user : felt, lockup: felt):
    let (res) = lp_balances.read(user=user)
    return (res[0],res[1])
end

####################################################################################
# @dev functions to set lp tokens by user
# @param input is
# - the user addy
# - the new lp tokens for the user
# - the new lockup for the user
####################################################################################
@external
func set_lp_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, amount : felt, lockup : felt):
    lp_caller()
    is_paused()
    lp_balances.write(user,(amount,lockup))
    return ()
end

####################################################################################
# @dev below is storage and get/set for cz state
# cz state stores 
# lp total - total lp tokens in issue
# capital total - total USDC reserves, notional number, not reduced by loans
# loan total - total loans made, the capital total - loan total gives you the remaining liquidity this should recon to actual USDC in CZCore
# insolvency total - if a loan is liquidated at a loss, the loss is accumulated in insolvency total
# this gives a know amount shortfall which can then be bridged per litepaper
# reward total - is the current rewards accrued so far, once distributed by the controller this get set back to 0
# different contract caller have different access to change cz state
# all the below functions allow one or more of cz state to be updated
####################################################################################
@storage_var
func cz_state() -> (res : (felt, felt, felt, felt, felt)):
end

####################################################################################
# @dev get cz state
# @return
# - total lp tokens in issue
# - total USDC reserves
# - total loans made 
# - total loss on insolvent loans
# - total current rewards accrued
####################################################################################
@view
func get_cz_state{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> 
	(lp_total : felt, capital_total : felt, loan_total : felt, insolvency_total : felt, reward_total : felt):
    let (res) = cz_state.read()
    return (res[0],res[1],res[2],res[3],res[4])
end

@external
func set_lp_capital_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_amount : felt, capital_amount : felt):
    lp_caller()
    is_paused()
    let (res) = cz_state.read()
    cz_state.write((lp_amount,capital_amount,res[2],res[3],res[4]))
    return ()
end

@external
func set_loan_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(loan_amount : felt):
    cb_caller()
    is_paused()
    let (res) = cz_state.read()
    cz_state.write((res[0], res[1], loan_amount, res[3], res[4]))
    return ()
end

@external
func set_captal_loan_reward_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(capital_amount : felt, loan_amount : felt, reward_amount : felt):
    cb_caller()
    is_paused()
    let (res) = cz_state.read()
    cz_state.write((res[0],capital_amount,loan_amount,res[3],reward_amount))
    return ()
end

@external
func set_reward_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    controller_caller()
    is_paused()
    let (res) = cz_state.read()
    cz_state.write((res[0],res[1],res[2],res[3],0))
    return ()
end

####################################################################################
# @dev the PP status by user
####################################################################################
@storage_var
func pp_status(user : felt) -> (status : (felt, felt, felt)):
end

####################################################################################
# @dev get the PP status of the given user
# @param the user address
# @return 
# - locked lp token which was the requirement at the time of locking
# - locked czt tokens
# - pp status 0 - not a pricing provider 1- valid pricing provider
####################################################################################
@view
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_locked : felt, cz_locked : felt, status : felt):
    let (res) = pp_status.read(user=user)
    return (res[0],res[1],res[2])
end

####################################################################################
# @dev functions to promote and demote pp
# @param 
# - user addy
# - the lp tokens of the user
# - the change amount - lp required if promoting or the lp locked if demoting
# - the czt required to promote
# - the lockup period on the lp tokens
# - promote true/false flag 1 - promote 0 - demote
####################################################################################
@external
func set_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        user : felt, lp_user : felt, lp_amount : felt, cz_amount : felt, lockup : felt, promote : felt):
    pp_caller()
    is_paused()
    if promote == 1:
        # @dev promote user to pp and lock lp and cz tokens
        lp_balances.write(user, (lp_user - lp_amount, lockup))
        pp_status.write(user, (lp_amount, cz_amount, 1))
    else:
        # @dev demote user from pp and return lp and cz tokens
        lp_balances.write(user, (lp_user + lp_amount, lockup))
        pp_status.write(user, (0, 0, 0))    
    end    
    return ()
end


####################################################################################
# @dev the CB loans by user
# functions support CB interface to create loans, repay loans, refinance loans and change collateral
####################################################################################
@storage_var
func cb_loan(user : felt) -> (res : (felt, felt, felt, felt, felt, felt, felt)):
end

####################################################################################
# @dev get the CB loan for a given user
# @param the user address
# @return 
# - has loan - 1 for true and 0 for false
# - notional or loan amount
# - collateral in weth
# - start time of the loan in timestamp, or time of last laon change
# - end time of the loan in timestamp
# - interest rate of the loan
# - historic accrual which is needed post loan changes so that accurate fees can be paid to LP/IF/GT on repayment
####################################################################################
@view
func get_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> 
        (has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt):
    let (res) = cb_loan.read(user=user)
    return (res[0], res[1], res[2], res[3], res[4], res[5], res[6])
end

####################################################################################
# @dev set the CB loan for a given user
# @param 
# - the user address 
# - has loan - 1 for true and 0 for false
# - notional or loan amount
# - collateral in weth
# - start time of the loan in timestamp, or time of last laon change
# - end time of the loan in timestamp
# - interest rate of the loan
# - historic accrual which is needed post loan changes so that accurate fees can be paid to LP/IF/GT on repayment
# - new flag, 1 if new loan which is not allowed when system paused 0, if existing loan which can be changed during pause
# if system paused should allow existing loan holders to repay or refinance or change collateral
####################################################################################
@external
func set_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, has_loan : felt, notional : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, new : felt):
    cb_caller()
    # @dev new loans not allowed when system paused, repay refinancing inc dec collateral still allowed
    if new == 1:
    	is_paused()
    	cb_loan.write(user,(has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual))
        return()
    else:
    	cb_loan.write(user,(has_loan, notional, collateral, start_ts, end_ts, rate, hist_accrual))
        return()
    end		
end

####################################################################################
# @dev functions that index stakers so can distribute rewards
# as new stakers join we record these in an index so that we can iterate to list to distribute
####################################################################################
@storage_var
func staker_index(index:felt) -> (user : felt):
end

####################################################################################
# @dev get index - user mapping
# @param index e.g. 5
# @return user addy
####################################################################################
@view
func get_staker_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(index : felt) -> (user : felt):
    let (user) = staker_index.read(index=index)
    return (user)
end

####################################################################################
# @dev set index - user mapping
# @param 
# - index 
# - user addy
####################################################################################
@external
func set_staker_index{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(index:felt,user : felt):
    gt_caller()
    is_paused()
    staker_index.write(index,user)
    return ()
end

####################################################################################
# @dev maps unique users to their stake, unclaimed rewards, old_user status
####################################################################################
@storage_var
func staker_details(user:felt) -> (res : (felt,felt,felt)):
end

####################################################################################
# @dev get user stake, unclaimed rewards, old_user status
# old user status is needed to decide whether we add user to index mapping, no need if old user
# @param 
# - user addy
# @return 
# - the czt tokens staked by the user
# - the distributed but still unclaimed rewards of the user
# - old user status needed for indexing
####################################################################################
@view
func get_staker_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user:felt) -> (gt_token : felt, unclaimed_reward : felt, old_user:felt):
    let (res) = staker_details.read(user=user)
    return (res[0],res[1],res[2])
end

####################################################################################
# @dev set user stake, unclaimed rewards, old_user status
# @param 
# - user addy
# - the czt tokens staked by the user
# - unclaimed rewards of the user
# since interacting with this user, they become an old user by default
# first time users will have old user status as 0
####################################################################################
@external
func set_staker_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, gt_token : felt, unclaimed_reward : felt):
    gt_caller()
    is_paused()
    staker_details.write(user,(gt_token,unclaimed_reward,1))
    return ()
end

####################################################################################
# @dev total amount staked and count of unique stakers
####################################################################################
@storage_var
func staker_total() -> (res : (felt,felt)):
end

####################################################################################
# @dev get total amount staked and count of unique stakers
# @return 
# - total czt staked in the protocol earning rewards
# - the index /count of unique stakers, needed for iteration in the distribute function in the controller
####################################################################################
@view
func get_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (stake_total : felt, index : felt):
    let (res) = staker_total.read()
    return (res[0],res[1])
end

####################################################################################
# @dev set total amount staked and count of unique stakers
# @param 
# - total czt staked in the protocol
# - the index /count of unique stakers
####################################################################################
@external
func set_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stake_total : felt, index : felt):
    gt_caller()
    is_paused()
    staker_total.write((stake_total,index))
    return ()
end
