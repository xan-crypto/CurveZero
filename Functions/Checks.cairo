####################################################################################
# @title Checks contract
# @dev all numbers passed into contract must be Math10xx8 type
# this is a group of useful functions that are needed by most of the contracts
# Functions include
# - check if the caller is the owner
# - check if the caller is the controller
# - check if current insurance shortfall ratio is below min level in Settings
# - check user has sufficient balance and return ERC-20 decimal amount
# - check sufficient number of PPs (pricing providers) vs min in settings
# - check sufficient collateral vs loan request
# - check current utilization be max level from Settings
# - check term of loan below max term
# - check loan range within range in Settings
# - calc the residual loan capital
# There is no owner addy or trusted addy here, these functions are imported to the relevant contracts
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_le, assert_nn_le, assert_in_range, assert_nn
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import Uint256
from Functions.Math10xx8 import Math10xx8_div, Math10xx8_mul, Math10xx8_convert_from, Math10xx8_zero, Math10xx8_convert_to, Math10xx8_ts, Math10xx8_add, Math10xx8_sub, Math10xx8_fromUint256, Math10xx8_fromFelt
from InterfaceAll import Settings, Erc20, Oracle

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
# @dev check system below min insurance shortfall ratio
# insurance shortfall is the total insolvent losses divided by the total capital in the system
# and this grows the system becomes more and more insolvent, settings ratio is set at 1%
# this stops other function like GTs taking CZT out of the system when a large loss occurs
# @param 
# - capital total from CZCore
# - insolvency total which is the accumulated losses from insolvent loans
# - min insurance shortfall ratio from settings
####################################################################################
func check_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(capital_total : felt, insolvency_total :felt, min_is_ratio :felt):
    alloc_locals
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
# - caller / users address
# - the erc20 addy, can be used for WETH USDC and CZT as long as same contract type
# - amount of token in Math10xx8 terms
# @return 
# - the amount of token in erc20 native contract terms
# recall that Math10xx8 is a different decimal system to 18 decimals which is the erc20 std at the moment
####################################################################################
func check_user_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(caller : felt, erc_addy : felt, amount : felt) -> (amount_erc : felt):
    alloc_locals
    let (caller_balance_unit : Uint256) = Erc20.ERC20_balanceOf(erc_addy, caller)
    let (caller_balance) = Math10xx8_fromUint256(caller_balance_unit)
    let (decimals) = Erc20.ERC20_decimals(erc_addy)
    let (amount_erc) = Math10xx8_convert_from(amount, decimals)
    with_attr error_message("Caller does not have sufficient funds."):
        assert_nn_le(amount_erc, caller_balance)
    end
    return(amount_erc)
end

####################################################################################
# @dev check eno pp for pricing, settings has min_pp
# @param 
# - settings addy so that we can get min pp accepted
# - number of PPs in current pricing request
####################################################################################
func check_min_pp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, num_pp : felt):
    alloc_locals
    let (convert_num_pp) = Math10xx8_fromFelt(num_pp)
    let (min_pp) = Settings.get_min_pp_accepted(settings_addy)
    with_attr error_message("Not enough PPs for valid pricing."):
        assert_le(min_pp, convert_num_pp)
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
    let (new_loan_total) = Math10xx8_add(notional,loan_total)
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
    let (min_loan,max_loan) = Settings.get_min_max_loan(settings_addy)
    with_attr error_message("Notional should be within min max loan range."):
       assert_in_range(notional, min_loan, max_loan)
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
