# LP contract
# all numbers passed into contract must be Math64x61 type

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_le, assert_in_range
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, ERC20
from Math.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add, Math64x61_convert_from, Math64x61_ts

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(deployer : felt):
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
# Trusted addy, only deployer can point contract to Trusted Addy contract
# addy of the Trusted Addy contract
@storage_var
func trusted_addy() -> (addy : felt):
end

# get the trusted contract addy
@view
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = trusted_addy.read()
    return (addy)
end

# set the trusted contract addy
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

##################################################################
# need to emit LP events so that we can do reporting / dashboard to monitor system
# dont need to emit total lp and total capital since can do that with history of changes
@event
func lp_token_change(addy : felt, lp_change : felt, capital_change : felt):
end

##################################################################
# LP contract functions
# issue LP tokens to user vs deposit
@external
func usdc_deposit_vs_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(usdc_deposit : felt) -> (lp_token : felt):
    
    alloc_locals
    # check that usdc depo within restricted deposit range
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (min_deposit, max_deposit) = Settings.get_min_max_deposit(settings_addy)
    with_attr error_message("LP deposit not in required range."):
        assert_in_range(usdc_deposit, min_deposit, max_deposit)
    end

    # check insurance shortfall ratio acceptable
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_shortfall) = CZCore.get_cz_state(czcore_addy)
    let (min_is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)   
    if capital_total == 0:  
        let (current_is_ratio) = 0
    else:
        let (current_is_ratio) = Math64x61_div(insolvency_shortfall, capital_total)
    end
    with_attr error_message("Insurance shortfall ratio too high."):
        assert_le(current_ratio, is_ratio)
    end

    # check user has sufficient USDC
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (user) = get_caller_address()
    let (usdc_user) = ERC20.ERC20_balanceOf(usdc_addy, user)
    let (usdc_decimals) = ERC20.ERC20_decimals(usdc_addy)
    # do decimal conversion so comparing like with like
    let (usdc_deposit_erc) = Math64x61_convert_from(usdc_deposit, usdc_decimals)
    with_attr error_message("User does not have sufficient funds."):
        assert_le(usdc_deposit_erc, usdc_user)
    end

    # other variables and calcs
    let (lockup_period) = Settings.get_lockup_period(settings_addy)
    let (block_ts) = Math64x61_ts()
    let (new_capital_total) = Math64x61_add(capital_total, usdc_deposit)

    # calc new lp total and new lp issuance
    if lp_total == 0:
        let new_lp_total = depo_USD
        let new_lp_issuance = depo_USD
        # transfer the actual USDC tokens to CZCore reserves - ERC decimal version
        CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, usdc_deposit_erc)
        # store all new data
        CZCore.set_lp_capital_total(czcore_addy, new_lp_total, new_capital_total)
        # mint the lp token
        let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
        let (temp1) = Math64x61_add(lp_user, new_lp_issuance)
        let (temp2) = Math64x61_add(block_ts, lockup_period)
        CZCore.set_lp_balance(czcore_addy, user, temp1, temp2)
        # event
        lp_token_change.emit(addy=user, lp_change=new_lp_issuance, capital_change=usdc_deposit)
        return (new_lp_issuance)
    else:
        let (temp3) = Math64x61_mul(new_capital_total, lp_total)
        let (new_lp_total) = Math64x61_div(temp3, capital_total)
        let (new_lp_issuance) = Math64x61_sub(new_lp_total, lp_total)
        # transfer the actual USDC tokens to CZCore reserves - ERC decimal version
        CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, usdc_deposit_erc)
        # store all new data
        CZCore.set_lp_capital_total(czcore_addy, new_lp_total, new_capital_total)
        # mint the lp token
        let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
        let (temp4) = Math64x61_add(lp_user, new_lp_issuance)
        let (temp5) = Math64x61_add(block_ts, lockup_period)
        CZCore.set_lp_balance(czcore_addy, user, temp4, temp5)
        # event
        lp_token_change.emit(addy=user, lp_change=new_lp_issuance, capital_change=usdc_deposit_erc)
        return (new_lp_issuance)
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
    let (current_ratio) = Math64x61_div(insolvency_shortfall, capital_total)
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
