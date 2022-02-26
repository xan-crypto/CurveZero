# Useful functions

func check_is_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (owner) = owner_addy.read()
    with_attr error_message("Only owner can access this."):
        assert caller = owner
    end
end

func check_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (min_is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)   
    if capital_total == 0:  
        let (current_is_ratio) = 0
    else:
        let (current_is_ratio) = Math64x61_div(insolvency_total, capital_total)
    end
    with_attr error_message("Insurance shortfall ratio too high."):
        assert_le(current_is_ratio, min_is_ratio)
    end
end

func check_user_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(erc_addy: felt, amount : felt) -> (erc_amount : felt):
    let (caller) = get_caller_address()
    let (caller_balance) = ERC20.ERC20_balanceOf(erc_addy, caller)
    let (erc_decimals) = ERC20.ERC20_decimals(erc_addy)
    let (erc_amount) = Math64x61_convert_from(amount, erc_decimals)
    with_attr error_message("Caller does not have sufficient funds."):
        assert_le(erc_amount, caller_balance)
    end
    return(erc_amount)
end
