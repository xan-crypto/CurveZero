####################################################################################
# @title LiquidityProvider contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - mint lp tokens by depositing USDC
# - burn lp token by withdrawing USDC 
# - value what their lp tokens are worth in USDC
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_le, assert_in_range
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.uint256 import Uint256
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add, Math10xx8_convert_from, Math10xx8_ts, Math10xx8_fromUint256
from Functions.Checks import check_is_owner, check_user_balance, check_insurance_shortfall_ratio

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
# TODO check that this reports correctly for negative / reductions
# type 1 - mint type 0 - burn
####################################################################################
@event
func event_lp_token(addy : felt, lp_change : felt, capital_change : felt, type : felt):
end

####################################################################################
# @dev mint LP tokens for user vs deposit of USDC
# @param input is the USDC depo from user
####################################################################################
@external
func mint_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(usdc_deposit : felt) -> ():
    alloc_locals
    # @dev check that usdc deposit within restricted deposit range
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (min_deposit, max_deposit) = Settings.get_min_max_deposit(settings_addy)
    with_attr error_message("Deposit not in required range."):
        assert_in_range(usdc_deposit, min_deposit, max_deposit) 
    end

    # @dev check insurance shortfall ratio acceptable
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (min_is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)   
    check_insurance_shortfall_ratio(capital_total, insolvency_total, min_is_ratio)

    # @dev check user has sufficient USDC
    let (user) = get_caller_address()
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (usdc_deposit_erc) = check_user_balance(user, usdc_addy, usdc_deposit)

    # @dev other variables and calcs
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (accrued_capital_total) = Math10xx8_add(capital_total, accrued_interest_total)
    let (new_capital_total) = Math10xx8_add(capital_total, usdc_deposit)
    let (new_accrued_capital_total) = Math10xx8_add(accrued_capital_total, usdc_deposit)

    # @dev transfer the USDC, mint the lp token and update variables
    let (new_lp_total, lp_issuance) = lp_update(lp_total, usdc_deposit, new_accrued_capital_total, accrued_capital_total)
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, usdc_deposit_erc)
    CZCore.erc20_mint(czcore_addy, lpt_addy, user, lp_issuance)
    CZCore.set_cz_state(czcore_addy, new_lp_total, new_capital_total, loan_total, insolvency_total, reward_total)
    # @dev emit event 
    event_lp_token.emit(addy=user, lp_change=lp_issuance, capital_change=usdc_deposit, type=1)
    return ()
end

####################################################################################
# @dev calcultes new lp total and lp issuance, used within the mint_lp_token function
# @param input is
# - the current total lp tokens from CZCore
# - the USDC depo from user
# - the new capital + accrued interest total post the deposit above
# - the current capital + accrued interest total from CZCore
# @return 
# - the new total lp tokens to be stored in CZCore
# - the lp issuance for the user
####################################################################################
func lp_update{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_total : felt, usdc_deposit : felt, new_accrued_capital_total : felt, accrued_capital_total : felt) -> (new_lp_total : felt, lp_issuance : felt):
    alloc_locals
    if lp_total == 0:
        let new_lp_total = usdc_deposit
        let lp_issuance = usdc_deposit
        return(new_lp_total, lp_issuance)
    else:
        let (capital_ratio) = Math10xx8_div(new_accrued_capital_total, accrued_capital_total)
        let (new_lp_total) = Math10xx8_mul(lp_total, capital_ratio)
        let (lp_issuance) = Math10xx8_sub(new_lp_total, lp_total)
        return(new_lp_total, lp_issuance)
    end
end

####################################################################################
# @dev burn LP tokens from user and withdraw USDC
# @param input is the lp tokens user wants to burn
# @return the USDC that has been withdrawn for the user
####################################################################################
@external
func burn_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt) -> ():
    alloc_locals
    # @dev check insurance shortfall ratio acceptable
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (min_is_ratio) = Settings.get_insurance_shortfall_ratio(settings_addy)   
    check_insurance_shortfall_ratio(capital_total, insolvency_total, min_is_ratio)

    # @dev verify that the amount lp withdraws is positive and below total.
    with_attr error_message("Amount must be positive and below LP total available."):
        assert_nn_le(lp_token, lp_total)
    end

    # @dev verify user has sufficient LP tokens to redeem
    let (user) = get_caller_address()
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lpt_burn_erc) = check_user_balance(user, lpt_addy, lp_token)

    # @dev other variables and calcs
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (accrued_capital_total) = Math10xx8_add(capital_total, accrued_interest_total)
    let (new_lp_total) = Math10xx8_sub(lp_total, lp_token)
    let (lp_ratio) = Math10xx8_div(new_lp_total, lp_total)   
    let (new_accrued_capital_total) = Math10xx8_mul(accrued_capital_total, lp_ratio)
    let (capital_redeem) = Math10xx8_sub(accrued_capital_total, new_accrued_capital_total)
    let (new_capital_total) = Math10xx8_sub(capital_total, capital_redeem)

    # @dev check czcore has sufficient USDC
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (capital_redeem_erc) = check_user_balance(czcore_addy, usdc_addy, capital_redeem)

    # @dev transfer the USDC, burn the lp token and update variables
    CZCore.erc20_burn(czcore_addy, lpt_addy, user, lp_token)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, capital_redeem_erc)
    CZCore.set_cz_state(czcore_addy, new_lp_total, new_capital_total, loan_total, insolvency_total, reward_total)
    # @dev emit event
    event_lp_token.emit(addy=user, lp_change=-lp_token, capital_change=-capital_redeem, type=0)
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
func value_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_user : felt, usd_value):
    alloc_locals
    # @dev get variables
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (accrued_interest_total) = CZCore.set_update_accrual(czcore_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    let (accrued_capital_total) = Math10xx8_add(capital_total, accrued_interest_total)
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lp_user_unit : Uint256) = Erc20.ERC20_balanceOf(lpt_addy, user)
    let (lp_user) = Math10xx8_fromUint256(lp_user_unit)

    # @dev calc user capital to return
    if lp_user == 0:
        return (0, 0)
    else:
        let (lp_ratio) = Math10xx8_div(lp_user, lp_total)
        let (capital_user) = Math10xx8_mul(lp_ratio, accrued_capital_total)
        return (lp_user, capital_user)
    end
end
