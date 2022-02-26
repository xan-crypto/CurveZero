# LP contract
# all numbers passed into contract must be Math64x61 type
# events include event_lp_token
# functions include mint_lp_token, burn_lp_token, value_lp_token

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_le, assert_in_range
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add, Math64x61_convert_from, Math64x61_ts
from Functions.Checks import check_is_owner, check_user_balance, check_insurance_shortfall_ratio

##################################################################
# addy of the owner
@storage_var
func owner_addy() -> (addy : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    owner_addy.write(owner)
    return ()
end

@view
func get_owner_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = owner_addy.read()
    return (addy)
end

##################################################################
# trusted addy where contract addys are stored, only owner can change this
@storage_var
func trusted_addy() -> (addy : felt):
end

@view
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
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

##################################################################
# emit LP events for reporting / dashboard to monitor system
@event
func event_lp_token(addy : felt, lp_change : felt, capital_change : felt):
end

##################################################################
# mint LP tokens for user vs deposit
@external
func mint_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(usdc_deposit : felt) -> (lp_token : felt):
    
    alloc_locals
    # check that usdc deposit within restricted deposit range
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (min_deposit, max_deposit) = Settings.get_min_max_deposit(settings_addy)
    with_attr error_message("Deposit not in required range."):
        assert_in_range(usdc_deposit, min_deposit, max_deposit)
    end

    # check insurance shortfall ratio acceptable
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (min_is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)   
    check_insurance_shortfall_ratio(capital_total, insolvency_total, min_is_ratio)

    # check user has sufficient USDC
    let (user) = get_caller_address()
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_deposit_erc) = check_user_balance(user, usdc_addy, usdc_deposit)

    # other variables and calcs
    let (lockup_period) = Settings.get_lockup_period(settings_addy)
    let (block_ts) = Math64x61_ts()
    let (new_capital_total) = Math64x61_add(capital_total, usdc_deposit)

    # transfer the USDC, mint the lp token and update variables
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, usdc_deposit_erc)
    let (new_lp_total, new_lp_issuance) = lp_update(lp_total, usdc_deposit, new_capital_total, capital_total)
    CZCore.set_lp_capital_total(czcore_addy, new_lp_total, new_capital_total)
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    let (new_lp_user) = Math64x61_add(lp_user, new_lp_issuance)
    let (new_lockup) = Math64x61_add(block_ts, lockup_period)
    CZCore.set_lp_balance(czcore_addy, user, new_lp_user, new_lockup)
    # event 
    event_lp_token.emit(addy=user, lp_change=new_lp_issuance, capital_change=usdc_deposit)
    return (new_lp_issuance)
end

# calc new lp total and issuance
func lp_update{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_total : felt, usdc_deposit: felt, new_capital_total : felt, capital_total: felt) -> (new_lp_total : felt, new_lp_issuance : felt):
    if lp_total == 0:
        let new_lp_total = usdc_deposit
        let new_lp_issuance = usdc_deposit
        return(new_lp_total, new_lp_issuance)
    else:
        let (new_capital_ratio) = Math64x61_div(new_capital_total, capital_total)
        let (new_lp_total) = Math64x61_mul(lp_total, new_capital_ratio)
        let (new_lp_issuance) = Math64x61_sub(new_lp_total, lp_total)
        return(new_lp_total, new_lp_issuance)
    end
end

# redeem LP tokens from user
@external
func usdc_withdraw_vs_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_withdraw : felt) -> (usdc : felt):
    
    alloc_locals
    # check insurance shortfall ratio acceptable
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)
    if capital_total == 0:  
        let (current_is_ratio) = 0
    else:
        let (current_is_ratio) = Math64x61_div(insolvency_shortfall, capital_total)
    end    
    with_attr error_message("Insurance shortfall ratio too high."):
        assert_le(current_ratio, is_ratio)
    end

    # can only withdraw if not in lock up
    let (user) = get_caller_address()
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    let (block_ts) = Math64x61_ts()
    with_attr error_message("Cant withdraw in lock up period."):
        assert_le(lockup, block_ts)
    end

    # verify that the amount is lp withdraw is positive and below total.
    with_attr error_message("Amount must be positive and below LP total available."):
        assert_nn_le(lp_withdraw, lp_total)
    end
    # verify user has sufficient LP tokens to redeem
    with_attr error_message("Insufficent LP tokens to redeem."):
        assert_le(lp_withdraw, lp_user)
    end

    # other variables and calcs
    let (new_lp_total) = Math64x61_sub(lp_total, lp_withdraw)
    let (temp1) = Math64x61_mul(new_lp_total, capital_total)
    let (new_capital_total) = Math64x61_div(temp1, lp_total)
    let (new_capital_redeem) = Math64x61_sub(capital_total, new_capital_total)

    # transfer the actual USDC tokens from CZCore reserves
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (usdc_decimals) = ERC20.ERC20_decimals(usdc_addy)
    # do decimal conversion so comparing like with like
    let (new_capital_redeem_erc) = Math64x61_convert_from(new_capital_redeem, usdc_decimals)
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, czcore_addy, user, new_capital_redeem_erc)

    # store all new data
    CZCore.set_lp_capital_total(czcore_addy, new_lp_total, new_capital_total)
    # burn lp tokens
    let (temp2) = Math64x61_sub(lp_user, lp_withdraw)
    CZCore.set_lp_balance(czcore_addy, user, temp2, lockup)
    # event
    lp_token_change.emit(addy=user, lp_change=-lp_withdraw, capital_change=-new_capital_redeem)
    return (new_capital_redeem)
end

# whats my LP tokens worth
@view
func lp_token_worth{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (usd : felt, lockup : felt):
    
    alloc_locals
    # get variables
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)

    # calc user capital to return
    if lp_user == 0:
        return (0, 0)
    else:
        let (temp1) = Math64x61_mul(lp_user, capital_total)
        let (capital_user) = Math64x61_div(temp1, lp_total)
        return (capital_user, lockup)
    end
end
