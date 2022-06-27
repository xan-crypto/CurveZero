####################################################################################
# @title LiquidityProvider contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - mint lp tokens by depositing USDC
# - burn lp token by withdrawing USDC 
# - value what their lp tokens are worth in USDC
# - get the value of 1 lp token in USDC
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math10xx8 import Math10xx8_mul, Math10xx8_div, Math10xx8_sub, Math10xx8_add
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
# user addy, new user lp balance, lp change, captial change and type 1 - mint type 0 - burn
####################################################################################
@event
func event_lp_token(addy : felt, lp_balance : felt, lp_change : felt, capital_change : felt, type : felt):
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
    check_min_max_deposit(settings_addy, usdc_deposit)

    # @dev check insurance shortfall ratio acceptable
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    check_insurance_shortfall_ratio(settings_addy, capital_total, insolvency_total)

    # @dev check user has sufficient USDC
    let (user) = get_caller_address()
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    check_user_balance(usdc_addy, user, usdc_deposit)

    # @dev get user current lp token balance
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lp_balance) = get_user_balance(lpt_addy, user)

    # @dev update incremental accrued interest and calc capital + lp accrued interest
    let (accrued_capital_total) = calc_capital_lp_accrued_interest(czcore_addy, settings_addy, capital_total)
    let (new_capital_total) = Math10xx8_add(capital_total, usdc_deposit)

    # @dev check deposit does not result in max capital breach
    check_max_capital(settings_addy, new_capital_total)

    # dev get lp issuance and new lp total
    let (new_lp_total, lp_issuance) = lp_update(lp_total, usdc_deposit, accrued_capital_total)

    # @dev transfer the USDC, update variables and mint the lp token
    CZCore.erc20_transferFrom(czcore_addy, usdc_addy, user, czcore_addy, usdc_deposit)
    CZCore.set_cz_state(czcore_addy, new_lp_total, new_capital_total, loan_total, insolvency_total, reward_total)
    CZCore.erc20_mint(czcore_addy, lpt_addy, user, lp_issuance)
    
    # @dev emit event, need user balance at end for lender count, can remove if ERC20 supports this
    let (new_lp_balance) = Math10xx8_add(lp_balance, lp_issuance)
    event_lp_token.emit(user, new_lp_balance, lp_issuance, usdc_deposit, 1)
    return ()
end

####################################################################################
# @dev calcultes new lp total and lp issuance, used within the mint_lp_token function
# @param input is
# - the current total lp tokens from CZCore
# - the USDC depo from user
# - the current capital + accrued interest total from CZCore
# @return 
# - the new total lp tokens to be stored in CZCore
# - the lp issuance for the user
####################################################################################
func lp_update{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_total : felt, usdc_deposit : felt, accrued_capital_total : felt) -> (new_lp_total : felt, lp_issuance : felt):
    alloc_locals
    if lp_total == 0:
        let new_lp_total = usdc_deposit
        let lp_issuance = usdc_deposit
        return(new_lp_total, lp_issuance)
    else:
        let (new_accrued_capital_total) = Math10xx8_add(accrued_capital_total, usdc_deposit)
        let (capital_ratio) = Math10xx8_div(new_accrued_capital_total, accrued_capital_total)
        let (new_lp_total) = Math10xx8_mul(lp_total, capital_ratio)
        let (lp_issuance) = Math10xx8_sub(new_lp_total, lp_total)
        return(new_lp_total, lp_issuance)
    end
end

####################################################################################
# @dev burn LP tokens from user and withdraw USDC
# @param input is the lp tokens user wants to burn
####################################################################################
@external
func burn_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt) -> ():
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
    check_user_balance(lpt_addy, user, lp_token)

    # @dev get user current lp token balance
    let (lp_balance) = get_user_balance(lpt_addy, user)
    
    # @dev update incremental accrued interest and calc capital + lp accrued interest
    let (accrued_capital_total) = calc_capital_lp_accrued_interest(czcore_addy, settings_addy, capital_total)
    
    # dev get capital redeemed and new lp total
    let (new_lp_total) = Math10xx8_sub(lp_total, lp_token)
    let (lp_ratio) = Math10xx8_div(new_lp_total, lp_total)   
    let (new_accrued_capital_total) = Math10xx8_mul(accrued_capital_total, lp_ratio)
    let (capital_redeem) = Math10xx8_sub(accrued_capital_total, new_accrued_capital_total)
    let (new_capital_total) = Math10xx8_sub(capital_total, capital_redeem)

    # @dev burn the lp token, update variables and transfer the USDC
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    CZCore.erc20_burn(czcore_addy, lpt_addy, user, lp_token)
    CZCore.set_cz_state(czcore_addy, new_lp_total, new_capital_total, loan_total, insolvency_total, reward_total)
    CZCore.erc20_transfer(czcore_addy, usdc_addy, user, capital_redeem)    
    
    # @dev emit event, need user balance at end for lender count, can remove if ERC20 supports this
    let (new_lp_balance) = Math10xx8_sub(lp_balance, lp_token)
    event_lp_token.emit(user, new_lp_balance, lp_token, capital_redeem, 0)
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
func value_user_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (lp_balance : felt, usd_value):
    alloc_locals
    # @dev get user lp balance
    let (_trusted_addy) = trusted_addy.read()
    let (lpt_addy) = TrustedAddy.get_lpt_addy(_trusted_addy)
    let (lp_balance) = get_user_balance(lpt_addy, user)
    # @dev calc user capital
    let (usd_value) = value_lp_token()
    let (capital_user) = Math10xx8_mul(usd_value, lp_balance)
    return (lp_balance, capital_user)
end

####################################################################################
# @dev values 1 LP token in USDC terms
# @return 
# - the USDC value of 1 lp token
####################################################################################
@view
func value_lp_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (usd_value):
    alloc_locals
    # @dev get variables
    let (_trusted_addy) = trusted_addy.read()
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    # @dev update incremental accrued interest and calc capital + lp accrued interest
    let (accrued_capital_total) = calc_capital_lp_accrued_interest(czcore_addy, settings_addy, capital_total)
    if lp_total == 0:
        return (0)
    else:
        let (usd_value) = Math10xx8_div(accrued_capital_total, lp_total)
        return (usd_value)
    end
end