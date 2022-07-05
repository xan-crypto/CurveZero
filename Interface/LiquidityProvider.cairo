####################################################################################
# @title LiquidityProvider contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - deposit USDC which mints lp tokens
# - withdraw USDC which burns lp tokens
# - withdraw all USDC which burn all lp tokens (UX to simplify since lp position can be 8 decimals)
# - value what their lp tokens are worth in USDC
# - value what 1 lp token is worth in USDC
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add, Math10xx8_one
from Functions.Checks import check_is_owner, check_user_balance, get_user_balance, check_insurance_shortfall_ratio, check_min_max_deposit, check_max_capital, calc_capital_lp_accrued_interest

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
# this allows for upgradability of this contract
####################################################################################
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

####################################################################################
# @dev storage for the trusted addy contract
# the TrustedAddy contract stores all the contract addys
####################################################################################
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

####################################################################################
# @dev emit LP events for reporting / dashboard to monitor system
# user addy, lp price, lp change, captial change and type
# use this on frontend, lp price and lp change needed in order to construct price basis for reporting
# capital change for UX so user can see historic in and out flows
# type also for UX type 1 - Deposit type 0 - Withdrawal
####################################################################################
@event
func event_lp_deposit_withdraw(addy : felt, lp_price : felt, lp_change : felt, capital_change : felt, type : felt):
end

####################################################################################
# @dev deposit USDC and mint LP tokens for user
# @param input is the USDC depo from user
####################################################################################
@external
func deposit_USDC{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(usdc_deposit : felt) -> ():
    alloc_locals
    # @dev check that usdc deposit within restricted deposit range
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    check_min_max_deposit(settings_addy, usdc_deposit)

    # @dev check insurance shortfall ratio acceptable
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_insurance_shortfall_ratio(settings_addy, capital_total, insolvency_total)

    # @dev check user has sufficient USDC
    let (user) = get_caller_address()
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    check_user_balance(usdc_addy, user, usdc_deposit)

    # @dev get user current lp token balance and lp price for issuance (lp price not affected by deposit/withdraw)
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lp_balance) = get_user_balance(lpt_addy, user)
    let (lp_price) = value_lp_token()
    let (lp_issuance) = Math10xx8_div(usdc_deposit, lp_price)

    # @dev get new lp total and capital total
    let (new_lp_total) = Math10xx8_add(lp_total, lp_issuance)
    let (new_capital_total) = Math10xx8_add(capital_total, usdc_deposit)

    # @dev check deposit does not result in max capital breach
    check_max_capital(settings_addy, new_capital_total)

    # @dev transfer the USDC, update variables and mint the lp token for user
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, usdc_deposit)
    CZCore.set_cz_state(czcore_addy, new_lp_total, new_capital_total, loan_total, insolvency_total, reward_total)
    CZCore.erc20_mint(czcore_addy, lpt_addy, user, lp_issuance)
    
    # @dev emit event, get lender count from ERC20 contract
    event_lp_deposit_withdraw.emit(user, lp_price, lp_issuance, usdc_deposit, 1)
    return ()
end

####################################################################################
# @dev withdraw USDC and burn LP tokens from user
# @param input is the USDC withdraw amount to make UX easy
####################################################################################
@external
func withdraw_USDC{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(usdc_withdraw : felt) -> ():
    alloc_locals
    # @dev check insurance shortfall ratio acceptable
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_insurance_shortfall_ratio(settings_addy, capital_total, insolvency_total)

    # @dev verify user has sufficient LP tokens to redeem
    let (user) = get_caller_address()
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lp_price) = value_lp_token()
    let (lp_redeem) = Math10xx8_div(usdc_withdraw, lp_price)
    check_user_balance(lpt_addy, user, lp_redeem)
   
    # dev get new lp total and new capital total
    let (new_lp_total) = Math10xx8_sub(lp_total, lp_redeem)
    let (new_capital_total) = Math10xx8_sub(capital_total, usdc_withdraw)

    # @dev burn the lp token, update variables and transfer the USDC
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    CZCore.erc20_burn(czcore_addy, lpt_addy, user, lp_redeem)
    CZCore.set_cz_state(czcore_addy, new_lp_total, new_capital_total, loan_total, insolvency_total, reward_total)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, usdc_withdraw)    
    
    # @dev emit event, get lender count from ERC20 contract
    event_lp_deposit_withdraw.emit(user, lp_price, lp_redeem, usdc_withdraw, 0)
    return ()
end

####################################################################################
# @dev withdraw all USDC and burns all the users remaining LP tokens
# this is mainly needed for UX because 8 decimal LP balances make it hard to redeem all
# @param / @return 
####################################################################################
@external
func withdraw_all_USDC{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> ():
    alloc_locals
    # @dev get user lp balance
    let (user) = get_caller_address()
    let (lp_balance, capital_user) = value_user_lp_token(user)
    withdraw_USDC(capital_user)
    return ()
end

####################################################################################
# @dev values a users LP tokens in USDC terms
# @param input is the users addy
# @return 
# - the lp tokens held by the user
# - the USDC value of those tokens
####################################################################################
@view
func value_user_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_balance : felt, capital_user):
    alloc_locals
    # @dev get user lp balance
    let (_trusted_addy) = trusted_addy.read()
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lp_balance) = get_user_balance(lpt_addy, user)
    # @dev calc user capital
    let (lp_price) = value_lp_token()
    let (capital_user) = Math10xx8_mul(lp_price, lp_balance)
    return (lp_balance, capital_user)
end

####################################################################################
# @dev values 1 LP token in USDC terms
# @return 
# - the USDC value of 1 lp token
####################################################################################
@view
func value_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lp_price):
    alloc_locals
    # @dev get variables
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    # @dev update incremental accrued interest and calc capital + lp accrued interest
    let (accrued_capital_total) = calc_capital_lp_accrued_interest(czcore_addy, settings_addy, capital_total)
    if lp_total == 0:
        let (lp_price) = Math10xx8_one()
        return (lp_price)
    else:
        let (lp_price) = Math10xx8_div(accrued_capital_total, lp_total)
        return (lp_price)
    end
end