####################################################################################
# @title Checks contract
# @dev all numbers passed into contract must be Math10xx8 type
# this is a group of useful functions that are needed by most of the contracts
# Functions include
# - check if the caller is owner
# - check if the caller is czcore
# - check if the caller is controller
# - check if deposit within min max range
# - check if current insurance shortfall ratio is below min level in Settings
# - check user has sufficient balance vs amount
# - check deposit does not breach max capital
# - check sufficient collateral vs loan request
# - check current utilization be max level from Settings
# - check term of loan below max term
# - check loan range within range in Settings
# - check that user has no loan
# - check that user has loan
# - check loan repayment does not exceed loan amount outstanding
# - check sufficient collateral for withdrawal
# - check notional and collateral positive
# - check gt stake
# - check insurance payout
# - calc the residual loan capital
# - calc accrued interest payment splits
# - calc loan outstanding
# - calc capital total and lp accrued interest
# - get user balance
# - convert amount to erc20 per decimals
# - loan not valid for liquidation
# There is no owner addy or trusted addy here, these functions are imported to the relevant contracts
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_le, assert_nn_le, assert_in_range, assert_nn, assert_not_zero
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import Uint256
from Functions.Math10xx8 import Math10xx8_div, Math10xx8_mul, Math10xx8_convert_from, Math10xx8_zero, Math10xx8_convert_to, Math10xx8_ts, Math10xx8_add, Math10xx8_sub, Math10xx8_fromUint256, Math10xx8_fromFelt
from InterfaceAll import Settings, Erc20, Oracle, CZCore

####################################################################################
# @dev check if owner
# @param owner addy passed from calling function
####################################################################################
func check_is_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("Only owner can access this."):
        assert caller = owner
    end
    return()
end

####################################################################################
# @dev check if caller is czcore
# @param caller addy
####################################################################################
func check_is_czcore{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addy : felt):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("Not authorised caller."):
        assert caller = addy
    end
    return()
end

####################################################################################
# @dev check if controller
# @param controller addy passed from calling function
####################################################################################
func check_is_controller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(controller : felt):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("Only controller can access this."):
        assert caller = controller
    end
    return()
end

####################################################################################
# @dev check that usdc deposit within restricted deposit range
# @param 
# - setting addy
# - usdc deposit in Math10xx8
####################################################################################
func check_min_max_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, usdc_deposit :felt):
    let (min_deposit, max_deposit) = Settings.get_min_max_deposit(settings_addy)
    with_attr error_message("Deposit not in required range."):
        assert_in_range(usdc_deposit, min_deposit, max_deposit) 
    end
    return()
end

####################################################################################
# @dev check system below min insurance shortfall ratio
# insurance shortfall is the total insolvent losses divided by the total capital in the system
# and this grows the system becomes more and more insolvent, settings ratio is set at 1%
# this stops other function like GTs taking CZT out of the system when a large loss occurs
# @param 
# - setting addy
# - capital total from CZCore
# - insolvency total which is the accumulated losses from insolvent loans
####################################################################################
func check_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, capital_total : felt, insolvency_total :felt):
    alloc_locals
    let (min_is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)   
    if capital_total == 0:  
        let (current_is_ratio) = Math10xx8_zero()
    else:
        let (current_is_ratio) = Math10xx8_div(insolvency_total, capital_total)
    end
    with_attr error_message("Insurance shortfall ratio too high."):
        assert_le(current_is_ratio, min_is_ratio)
    end
    return()
end

####################################################################################
# @dev check user has sufficient funds and return erc amount
# @param 
# - the erc20 addy, can be used for WETH USDC and CZT as long as same contract type
# - caller / users address
# - amount of token in Math10xx8 terms
# recall that Math10xx8 is a different decimal system to 18 decimals which is the erc20 std at the moment
####################################################################################
func check_user_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, caller : felt, amount : felt):
    alloc_locals
    let (balance) = get_user_balance(erc_addy, caller)
    with_attr error_message("Caller does not have sufficient funds."):
        assert_nn_le(amount, balance)
    end
    return()
end

####################################################################################
# @dev check check deposit does not result in max capital breach
# @param 
# - setting addy
# - new capital total
####################################################################################
func check_max_capital{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, new_capital : felt):
    alloc_locals
    let (max_capital) = Settings.get_max_capital(settings_addy)
    with_attr error_message("Deposit would exceed the max capital allowed in the protocol."):
        assert_le(new_capital, max_capital) 
    end
    return()
end

####################################################################################
# @dev test sufficient collateral to proceed vs notional of loan
# @param 
# - oracle addy so that we can get price and decimals
# - settings addy so that we can get ltc for WETH
# - notional of loan in Math10xx8
# - WETH collateral units in Math10xx8 1 WETH is 10**8
####################################################################################
func check_ltv{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(oracle_addy : felt, settings_addy : felt, notional : felt, collateral : felt):
    alloc_locals
    with_attr error_message("Collateral should be a positive number"):
        assert_nn(collateral)
    end
    let (price_erc) = Oracle.get_oracle_price(oracle_addy)
    let (decimals) = Oracle.get_oracle_decimals(oracle_addy)
    let (ltv) = Settings.get_weth_ltv(settings_addy)
    let (price) = Math10xx8_convert_to(price_erc, decimals)
    let (value_collateral) = Math10xx8_mul(price, collateral)
    let (max_loan) = Math10xx8_mul(value_collateral, ltv)
    with_attr error_message("Not sufficient collateral for loan"):
        assert_le(notional, max_loan)
    end
    return()
end

####################################################################################
# @dev check below utilization level post loan
# we check if the new loan would tip the system over the max util level
# @param 
# - settings addy so that we can get max utilization
# - notional of loan in Math10xx8
# - current total loans
# - current total capital
####################################################################################
func check_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, notional : felt, loan_total : felt, capital_total : felt):
    alloc_locals
    let (stop) = Settings.get_utilization(settings_addy)
    let (new_loan_total) = Math10xx8_add(notional, loan_total)
    let (utilization) = Math10xx8_div(new_loan_total, capital_total)
    with_attr error_message("Utilization to high, cannot issue loan."):
       assert_le(utilization, stop)
    end
    return()
end

####################################################################################
# @dev check end time less than setting max loan term and greater than current time
# @param 
# - settings addy so that we can get max loan term
# - block ts is the current timestamp of the last block in Math10xx8
# - the end time of the loan
####################################################################################
func check_max_term{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, block_ts : felt, end_ts : felt):
    alloc_locals
    let (max_term) = Settings.get_max_loan_term(settings_addy)
    let (max_end_ts) = Math10xx8_add(block_ts, max_term)
    with_attr error_message("Loan term should be within term range."):
       assert_in_range(end_ts, block_ts, max_end_ts)
    end
    return()
end

####################################################################################
# @dev check loan amount within correct ranges
# @param 
# - settings addy so that we can get loan ranges
# - notional of loan in Math10xx8
####################################################################################
func check_loan_range{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, notional : felt):
    alloc_locals
    let (min_loan, max_loan) = Settings.get_min_max_loan(settings_addy)
    with_attr error_message("Notional should be within min max loan range."):
       assert_in_range(notional, min_loan, max_loan)
    end
    return()
end

####################################################################################
# @dev check user has no loan
# @param 
# - czcore addy 
# - user addy
####################################################################################
func check_no_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(czcore_addy : felt, user : felt):
    alloc_locals
    let (old_notional, a, b, c, d, e, f, g, h) = CZCore.get_cb_loan(czcore_addy, user)
    with_attr error_message("User already has an existing loan, refinance loan instead."):
        assert old_notional = 0
    end
    return()
end

####################################################################################
# @dev check user has existing loan
# @param 
# - czcore addy 
# - user addy
####################################################################################
func check_user_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(notional : felt):
    alloc_locals
    with_attr error_message("User does not have an existing loan."):
        assert_not_zero(notional)
    end
    return()
end

####################################################################################
# @dev check loan repayment does not exceed loan amount outstanding
# @param 
# - repayment 
# - loan os
####################################################################################
func check_repayment_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(repay : felt, loan : felt):
    alloc_locals
    with_attr error_message("Partial repayment should be positive and at most the notional outstanding, consider using repay full."):
        assert_nn_le(repay, loan)
    end
    return()
end

####################################################################################
# @dev check sufficient collateral for withdrawal
# @param 
# - withdraw col
# - actual col
####################################################################################
func check_collateral_withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(withdraw : felt, collateral : felt):
    alloc_locals
    with_attr error_message("Collateral withdrawal should be positive and at most the user total collateral."):
       assert_nn_le(withdraw, collateral)
    end
    return()
end

####################################################################################
# @dev check notional and collateral positive
# @param 
# - withdraw col
# - actual col
####################################################################################
func check_notional_collateral{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(notional : felt, collateral : felt):
    alloc_locals
    with_attr error_message("Additional notional should be greater than or equal to zero."):
        assert_nn(notional)
    end
    with_attr error_message("Additional collateral should be greater than or equal to zero."):
        assert_nn(collateral)
    end
    return()
end

####################################################################################
# @dev check gt stake/unstake is positive
# @param 
# - gt tokens
####################################################################################
func check_gt_stake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt):
    alloc_locals
    with_attr error_message("GT stake/unstake should be positive amount."):
        assert_nn(gt_token)
    end
    return()
end

####################################################################################
# @dev check gt unstake doesnt exceed current user stake
# @param 
# - gt tokens
# - user current stake
####################################################################################
func check_gt_unstake{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(gt_token : felt, gt_user : felt):
    alloc_locals
    with_attr error_message("User does not have sufficient funds to unstake."):
        assert_le(gt_token, gt_user)
    end
    return()
end

####################################################################################
# @dev check insurance payout
# @param 
# - payout
# - insolvency total
####################################################################################
func check_if_payout{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(payout : felt, insolvency_total : felt):
    alloc_locals
    with_attr error_message("Can not payout more than the insolvency total."):
        assert_le(payout, insolvency_total)
    end
    return()
end

####################################################################################
# @dev this function calculates the residual loan capital repay amount
# max(0 , min(repay, notional - hist_repay))
# need this for the wt avg rate recal and the loan total recalc
# @param input is 
# - notional of current loan
# - history repayments made to date
# - new repayment
# @return
# - the loan repayment (to be used in blended wt avg calc and to update loan total in CZ state)
####################################################################################
func calc_residual_loan_capital{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(notional : felt, hist_repay : felt, repay : felt) -> (loan_repay : felt):
    alloc_locals
    let (no_notional_os) = is_le(notional, hist_repay)
    if no_notional_os == 1:
        return(0)
    end
    let (notional_os) = Math10xx8_sub(notional, hist_repay)
    let (repay_less_notional_os) = is_le(repay, notional_os)
    if repay_less_notional_os == 1:
        return(repay)
    else:
        return(notional_os)
    end
end

####################################################################################
# @dev calc accrued interest payment splits
# @param input is 
# - total accrued interest
# - split 1
# - split 2
# - split 3
# @return
# - fee 1
# - fee 2
# - fee 3
####################################################################################
func calc_accrued_interest_payments{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : felt, x : felt, y : felt, z : felt) -> (a : felt, b : felt, c : felt):
    alloc_locals
    let (a) = Math10xx8_mul(x, amount)
    let (b) = Math10xx8_mul(y, amount)
    let (c) = Math10xx8_mul(z, amount)
    return(a, b, c)
end

####################################################################################
# @dev calc loan amount outstanding
# @param input is 
# - notional
# - accrued interest
# - hist accrual
# - hist repay
# @return
# - loan amount os
####################################################################################
func calc_loan_outstanding{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(notional : felt, accrued_interest : felt, hist_accrual : felt, hist_repay : felt) -> (loan_os : felt):
    alloc_locals
    let (acrrued_notional) = Math10xx8_add(notional, accrued_interest)
    let (total_acrrued_notional) = Math10xx8_add(acrrued_notional, hist_accrual)
    let (total_acrrued_notional_os) = Math10xx8_sub(total_acrrued_notional, hist_repay)
    return(total_acrrued_notional_os)
end

####################################################################################
# @dev calc capital + lp accrued interest
# @param input is 
# - czcore addy
# - setting addy
# @return
# - capital + lp accrued interest
####################################################################################
func calc_capital_lp_accrued_interest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(czcore_addy : felt, settings_addy : felt, capital_total : felt) -> (accrued_capital_total : felt):
    alloc_locals
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (lp_split, if_split, gt_split) = Settings.get_accrued_interest_split(settings_addy)  
    let (lp_accrued_interest_total) = Math10xx8_mul(accrued_interest_total, lp_split)
    let (accrued_capital_total) = Math10xx8_add(capital_total, lp_accrued_interest_total)
    return(accrued_capital_total)
end

####################################################################################
# @dev get user balance
# @param 
# - caller / users address
# - the erc20 addy, can be used for WETH USDC and CZT as long as same contract type
# @return 
# - the balance in Math10xx8
####################################################################################
func get_user_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, caller : felt) -> (balance : felt):
    alloc_locals
    let (caller_balance_unit : Uint256) = Erc20.ERC20_balanceOf(erc_addy, caller)
    let (caller_balance) = Math10xx8_fromUint256(caller_balance_unit)
    let (decimals) = Erc20.ERC20_decimals(erc_addy)
    let (balance) = Math10xx8_convert_to(caller_balance, decimals)
    return(balance)
end

####################################################################################
# @dev convert Math10xx8 type to ERC20 std for transactions
# @param input is 
# - erc addy
# - Math10xx8 amount
# @return
# - erc20 amount
####################################################################################
func convert_to_erc{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy : felt, amount : felt) -> (amount_erc : felt):
    alloc_locals
    let (decimals) = Erc20.ERC20_decimals(erc_addy)
    let (amount_erc) = Math10xx8_convert_from(amount, decimals)
    return(amount_erc)
end

####################################################################################
# @dev loan not valid for liquidation error
####################################################################################
func loan_not_valid_liquidation{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    with_attr error_message("Loan is not valid for liquidation."):
        assert 0 = 1
    end
    return()
end