# Useful functions

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_le
from Functions.Math64x61 import Math64x61_div, Math64x61_convert_from, Math64x61_zero
from InterfaceAll import Erc20

func check_is_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    let (caller) = get_caller_address()
    with_attr error_message("Only owner can access this."):
        assert caller = owner
    end
    return()
end

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
