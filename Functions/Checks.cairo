# Useful functions

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_le
from Functions.Math64x61 import Math64x61_div, Math64x61_convert_from, Math64x61_zero, Math64x61_convert_to, Math64x61_ts, Math64x61_add
from InterfaceAll import Settings, Erc20, Oracle

# check if owner
func check_is_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    let (caller) = get_caller_address()
    with_attr error_message("Only owner can access this."):
        assert caller = owner
    end
    return()
end

# check system not below min is ratio
func check_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(capital_total : felt, insolvency_total :felt, min_is_ratio :felt):
    if capital_total == 0:  
        let (current_is_ratio) = Math64x61_zero()
    else:
        let (current_is_ratio) = Math64x61_div(insolvency_total, capital_total)
    end
    with_attr error_message("Insurance shortfall ratio too high."):
        assert_le(current_is_ratio, min_is_ratio)
    end
    return()
end

# check user has sufficient funds and return erc amount
func check_user_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(caller : felt, erc_addy: felt, amount : felt) -> (erc_amount : felt):
    alloc_locals
    let (caller_balance) = Erc20.ERC20_balanceOf(erc_addy, caller)
    let (erc_decimals) = Erc20.ERC20_decimals(erc_addy)
    let (erc_amount) = Math64x61_convert_from(amount, erc_decimals)
    with_attr error_message("Caller does not have sufficient funds."):
        assert_le(erc_amount, caller_balance)
    end
    return(erc_amount)
end

# check eno pp for pricing, settings has min_pp
func check_min_pp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, num_pp : felt):
    let (min_pp) = Settings.get_min_pp(setting_addy)
    with_attr error_message("Not enough PPs for valid pricing."):
        assert_le(min_pp, num_pp)
    end
    return()
end

# test sufficient collateral to proceed vs notional of loan
func check_ltv{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(oracle_addy : felt, settings_addy : felt, notional : felt, collateral : felt):
    let (erc_price) = Oracle.get_weth_price(oracle_addy)
    let (decimals) = Oracle.get_weth_decimals(oracle_addy)
    let (ltv) = Settings.get_weth_ltv(settings_addy)
    let (price) = Math64x61_convert_to(erc_price, decimals)
    let (value_collateral) = Math64x61_mul(price, collateral)
    let (max_loan) = Math64x61_mul(value_collateral, ltv)
    with_attr error_message("Not sufficient collateral for loan"):
        assert_le(notional, max_loan)
    end
    return()
end

# check below utilization level post loan
func check_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, notional : felt, loan_total : felt, capital_total : felt):
    let (stop) = Settings.get_utilization(settings_addy)
    let (new_loan_total) = Math64x61_add(notional,loan_total)
    let (utilization) = Math64x61_div(new_loan_total, capital_total)
    with_attr error_message("Utilization to high, cannot issue loan."):
       assert_le(utilization, stop)
    enn
    return()
end

# check end time less than setting max loan time
func check_max_term{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, end_ts : felt):
    let (block_ts) = Math64x61_ts()
    let (max_term) = Settings.get_max_loan_term(settings_addy)
    let (max_end_ts) = Math64x61_add(block_ts, max_term)
    with_attr error_message("Loan term should be within term range."):
       assert_in_range(end_ts, block_ts, max_end_ts)
    enn
    return()
end

# check loan amount within correct ranges
func check_loan_range{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(settings_addy : felt, notional : felt):
    let (min_loan,max_loan) = Settings.get_min_max_loan(settings_addy)
    with_attr error_message("Notional should be within min max loan range."):
       assert_in_range(notional, min_loan, max_loan)
    enn
    return()
end
