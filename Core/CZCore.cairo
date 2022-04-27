####################################################################################
# @title CZCore contract
# @dev all numbers passed into contract must be Math10xx8 type
# all interactions with reserves or state should flow through here
# the user / authorised contracts can
# - get the owner addy
# - get/set the TrustedAddy contract address where all contract addys are stored
# - transfer erc20 tokens from user to CZCore
# - transfer erc20 tokens to addy from CZCore
# - mint/burn LP tokens for a user (erc20 tokens equivalent)
# - get/set cz state (lp total, capital total, loan total, insolvency total, reward total)
# - get/set accrued interest state (accrued interest total, weighted average rate, last accrual ts)
# - get/set PP status (lp tokens locked, czt tokens locked, lockup timestamp post pricing, PP status)
# - get/set a user loan
# - get/set index of stakers needed for distributions
# - get/set a users stake and unclaimed rewards
# - get/set the total stake and index/count of stakers
# This contract addy will be stored in the TrustedAddy contract
# This contract is the main contract of the CurveZero protocol
# most other contracts can be easily swapped out, this is not true of CZCore because of the total/user state and reserves stored here
# for CZCore upgrade, a new version is needed, the Settings contract can be changed to push liquidity out of the older version
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_le
from InterfaceAll import TrustedAddy, Controller, Erc20
from Functions.Math10xx8 import Math10xx8_toUint256, Math10xx8_fromUint256, Math10xx8_ts, Math10xx8_year, Math10xx8_add, Math10xx8_sub, Math10xx8_mul, Math10xx8_div
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
# @dev useful 
# below functions are all specific to CZCore so no need to move to Checks contract
# functions below include
# - check if system is currently paused
# - check if caller is authorised i.e. either LP, PP, CB, LL, GT, IF or Controller contract
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

func authorised_callers{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    # @dev this has been optimised for the most frequent callers
    # priority is CB LP GT LL PP Controller and lastly IF
    let (cb_addy) = TrustedAddy.get_cb_addy(_trusted_addy)
    if caller == cb_addy:
    	return()
    end    
    let (lp_addy) = TrustedAddy.get_lp_addy(_trusted_addy)
    if caller == lp_addy:
    	return()
    end
    let (gt_addy) = TrustedAddy.get_gt_addy(_trusted_addy)
    if caller == gt_addy:
    	return()
    end
    let (ll_addy) = TrustedAddy.get_ll_addy(_trusted_addy)
    if caller == ll_addy:
    	return()
    end
    let (pp_addy) = TrustedAddy.get_pp_addy(_trusted_addy)
    if caller == pp_addy:
    	return()
    end    
    let (controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    if caller == controller_addy:
    	return()
    end
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
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
func erc20_transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, sender : felt, recipient : felt, amount : felt):
    alloc_locals
    authorised_callers()
    # @dev return insufficient allownace 
    with_attr error_message("Insufficient Allowance"):
        let (allowance_unit) = Erc20.ERC20_allowance(erc_addy, sender, recipient)
        let (allowance) = Math10xx8_fromUint256(allowance_unit)
        assert_le(amount, allowance)
    end
    let (amount_unit) = Math10xx8_toUint256(amount)
    Erc20.ERC20_transferFrom(erc_addy, sender=sender, recipient=recipient, amount=amount_unit)
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
func erc20_transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, recipient : felt, amount : felt):
    alloc_locals
    authorised_callers()
    let (amount_unit) = Math10xx8_toUint256(amount)
    Erc20.ERC20_transfer(erc_addy, recipient=recipient, amount=amount_unit)
    return ()
end 

####################################################################################
# @dev this is a pass thru function to the custom ERC-20 LP token contract
# - this is used to mint LP tokens for the user
# @param input is
# - the erc20 contract address
# - the recipient of the LP tokens
# - the amount in erc20 decimal format converted prior to being sent here
#################################################################################### 
@external
func erc20_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, recipient : felt, amount : felt):
    alloc_locals
    authorised_callers()
    is_paused()
    let (amount_unit) = Math10xx8_toUint256(amount)
    Erc20.ERC20_mint(erc_addy, recipient=recipient, amount=amount_unit)
    return ()
end

####################################################################################
# @dev this is a pass thru function to the custom ERC-20 LP token contract
# - this is used to burn LP tokens of the user
# @param input is
# - the erc20 contract address
# - the account whose LP tokens are getting burnt
# - the amount in erc20 decimal format converted prior to being sent here
#################################################################################### 
@external
func erc20_burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, account : felt, amount : felt):
    alloc_locals
    authorised_callers()
    is_paused()
    # @dev return insufficient balance
    # dupe check on balance? will this be done in the erc20 contract
    with_attr error_message("Insufficient Balance"):
        let (balance_unit) = Erc20.ERC20_balanceOf(erc_addy, account)
        let (balance) = Math10xx8_fromUint256(balance_unit)
        assert_le(amount, balance)
    end
    let (amount_unit) = Math10xx8_toUint256(amount)
    Erc20.ERC20_burn(erc_addy, account=account, amount=amount_unit)
    return ()
end

####################################################################################
# @dev accrued interest details storage
# the accrued interest total (when added with capital total, gives total asset pot of LPs)
# the weighted average simple rate (this is weighted by the notional of each loan)
# the last accrual ts (when last was the loan book accrued, any new accrual is from this point to current block timestamp)
####################################################################################
@storage_var
func accrued_interest() -> (res : (felt, felt, felt)):
end

####################################################################################
# @dev functions to get accrual interest details
# @return 
# - the accrued interest total
# - the weighted avg simple interest rate
# - last ts of interest accrual
####################################################################################
@view
func get_accrued_interest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (accrued_interest_total : felt, wt_avg_rate : felt, last_accrual_ts : felt):
    let (res) = accrued_interest.read()
    return (res[0], res[1], res[2])
end

####################################################################################
# @dev update accrual to current block timestamp
# using the weight avg simple interest rate, we accrue the total loan book from last accrual ts to current block ts
# @return
# - the latest accrued interest total to current block timestamp
####################################################################################
@external
func set_update_accrual{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (accrued_interest_total : felt):
    alloc_locals
    authorised_callers()
    let (ai) = accrued_interest.read()
    let (cz) = cz_state.read()
    let (block_ts) = Math10xx8_ts()
    let (year_secs) = Math10xx8_year()

    # @dev calc additional accrued interest on the loan book, update vars and return
    let (diff_ts) = Math10xx8_sub(block_ts, ai[2])
    let (year_frac) = Math10xx8_div(diff_ts, year_secs)
    let (rate_year_frac) = Math10xx8_mul(ai[1], year_frac)
    let (accrued_interest_add) = Math10xx8_mul(cz[2], rate_year_frac)
    let (new_accrued_interest_total) = Math10xx8_add(ai[0], accrued_interest_add)
    accrued_interest.write((new_accrued_interest_total, ai[1], block_ts))
    return (new_accrued_interest_total)
end

####################################################################################
# @dev update wt avg rate when new exposure added / removed
# @param 
# - new loan amount to be blended in to the wt avg
# - rate for the new loan
# - 1 for adding exposure 0 for removing exposure
####################################################################################
@external
func set_update_rate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_loan : felt, new_rate : felt, add_remove : felt) -> ():
    alloc_locals
    authorised_callers()
    let (ai) = accrued_interest.read()
    let (cz) = cz_state.read()
    let (old_exposure) = Math10xx8_mul(cz[2], ai[1])
    let (new_exposure) = Math10xx8_mul(new_loan, new_rate)

    if add_remove == 1:
        let (total_exposure) = Math10xx8_add(old_exposure, new_exposure)
        let (new_loan_total) = Math10xx8_add(cz[2], new_loan)
        let (new_wt_avg_rate) = Math10xx8_div(total_exposure, new_loan_total)
        accrued_interest.write((ai[0], new_wt_avg_rate, ai[2]))
        return()
    else:
        # @dev special check needed for remove
        let (test) = is_le(cz[2], new_loan)
        if test == 1:
            accrued_interest.write((ai[0], 0, ai[2]))
        else:
            let (total_exposure) = Math10xx8_sub(old_exposure, new_exposure)
            let (new_loan_total) = Math10xx8_sub(cz[2], new_loan)
            let (new_wt_avg_rate) = Math10xx8_div(total_exposure, new_loan_total)
            accrued_interest.write((ai[0], new_wt_avg_rate, ai[2]))
        end
        return()
    end
end

####################################################################################
# @dev payment received decreases accrual interest total
# @param 
# - the actual payment of accrued interest on the loan, no splits yet
####################################################################################
@external
func set_reduce_accrual{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(payment : felt) -> ():
    alloc_locals
    authorised_callers()
    let (ai) = accrued_interest.read()
    let (test_accrued_less_payment) = is_le(ai[0], payment)
    if test_accrued_less_payment == 1:
        accrued_interest.write((0, ai[1], ai[2]))
    else:
        let (new_accrued_interest_total) = Math10xx8_sub(ai[0], payment)
        accrued_interest.write((new_accrued_interest_total, ai[1], ai[2]))
    end
    return()
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
# all the below functions allow one or more of cz state to be updated
####################################################################################
@storage_var
func cz_state() -> (res : (felt, felt, felt, felt, felt)):
end

####################################################################################
# @dev get / set cz state
# @param @return
# - total lp tokens in issue
# - total USDC reserves
# - total loans made (represents cashflow, actual money out of the protocol / not accrued interest)
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
func set_cz_state{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_total : felt, capital_total : felt, loan_total : felt, insolvency_total : felt, reward_total : felt):
    authorised_callers()
    cz_state.write((lp_total, capital_total, loan_total, insolvency_total, reward_total))
    return ()
end

####################################################################################
# @dev the PP status by user
####################################################################################
@storage_var
func pp_status(user : felt) -> (status : (felt, felt, felt, felt)):
end

####################################################################################
# @dev get the PP status of the given user
# @param the user address
# @return 
# - locked lp tokens which was the requirement at the time of locking
# - locked czt tokens which was the requirement at the time of locking
# - lock timestamp, 7days post a valid pricing requestion submission
# - pp status 0 - not a pricing provider 1 - valid pricing provider
####################################################################################
@view
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_locked : felt, cz_locked : felt, lock_ts : felt, status : felt):
    let (res) = pp_status.read(user=user)
    return (res[0],res[1],res[2],res[3])
end

####################################################################################
# @dev functions to promote and demote pp
# @param 
# - user addy
# - lp required when promoting
# - czt required when promoting
# - the lockup period on the PP post pricing submission
# - promote true/false flag 1 - promote 0 - demote
####################################################################################
@external
func set_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        user : felt, lp_locked : felt, cz_locked : felt, lock_ts : felt, status : felt):
    authorised_callers()
    is_paused()
    pp_status.write(user, (lp_locked, cz_locked, lock_ts, status))
    return ()
end

####################################################################################
# @dev the CB loans by user
# functions support CB interface to create loans, repay loans, refinance loans and change collateral
####################################################################################
@storage_var
func cb_loan(user : felt) -> (res : (felt, felt, felt, felt, felt, felt, felt, felt, felt)):
end

####################################################################################
# @dev get the CB loan for a given user
# @param the user address
# @return 
# - notional or loan amount
# - collateral in weth
# - start time of the loan in timestamp, mainly for UX
# - reval time of last loan change (start if new loan or latest repay date or latest refinancing date)
# - end time of the loan in timestamp
# - interest rate of the loan
# - historic accrual which is needed post loan changes so that accurate fees can be paid to LP/IF/GT on repayment
# - all historic repayments made to date
# - liquidate me flag, user can give approval to LLs to liquidate their position (cant repay and want to close now)
####################################################################################
@view
func get_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> 
        (notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt):
    let (res) = cb_loan.read(user=user)
    return (res[0], res[1], res[2], res[3], res[4], res[5], res[6], res[7], res[8])
end

####################################################################################
# @dev set the CB loan for a given user
# @param 
# - the user address 
# - notional or loan amount
# - collateral in weth
# - start time of the loan in timestamp, or time of last laon change
# - end time of the loan in timestamp
# - interest rate of the loan
# - historic accrual which is needed post loan changes so that accurate fees can be paid to LP/IF/GT on repayment
# - total repayments made to date
# - liquidate me flag
# - new flag, 1 - new loan which is not allowed when system paused, 0 - existing loan which can be changed during pause
# if system paused should allow existing loan holders to repay or refinance or change collateral
####################################################################################
@external
func set_cb_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt, new : felt):
    authorised_callers()
    # @dev new loans not allowed when system paused, repay refinancing inc dec collateral still allowed
    if new == 1:
    	is_paused()
    	cb_loan.write(user, (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me))
        return()
    else:
    	cb_loan.write(user, (notional, collateral, start_ts, reval_ts, end_ts, rate, hist_accrual, hist_repay, liquidate_me))
        return()
    end		
end

####################################################################################
# @dev functions that index stakers so can distribute rewards
# as new stakers join we record these in an index so that we can iterate to list to distribute
####################################################################################
@storage_var
func staker_index(index : felt) -> (user : felt):
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
    authorised_callers()
    is_paused()
    staker_index.write(index,user)
    return ()
end

####################################################################################
# @dev maps unique users to their stake, unclaimed rewards, old_user status
####################################################################################
@storage_var
func staker_details(user : felt) -> (res : (felt,felt,felt)):
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
func get_staker_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user:felt) -> (gt_token : felt, unclaimed_reward : felt, old_user : felt):
    let (res) = staker_details.read(user=user)
    return (res[0], res[1], res[2])
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
    authorised_callers()
    is_paused()
    staker_details.write(user,(gt_token, unclaimed_reward, 1))
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
    return (res[0], res[1])
end

####################################################################################
# @dev set total amount staked and count of unique stakers
# @param 
# - total czt staked in the protocol
# - the index /count of unique stakers
####################################################################################
@external
func set_staker_total{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stake_total : felt, index : felt):
    authorised_callers()
    is_paused()
    staker_total.write((stake_total, index))
    return ()
end
