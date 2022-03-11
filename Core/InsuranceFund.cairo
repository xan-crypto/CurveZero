####################################################################################
# @title InsuranceFund contract
# @dev all numbers passed into contract must be Math10xx8 type
# User can call
# - insurance fund value, this is the USDC balance of the insurance fund - any user can call
# - insurance fund payout, this effectively refunds CZCore for any some amount of the insolvency loss - only owner can call
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Erc20
from starkware.cairo.common.uint256 import Uint256
from Functions.Math10xx8 import Math10xx8_sub, Math10xx8_add, Math10xx8_convert_to, Math10xx8_fromUint256, Math10xx8_toUint256
from Functions.Checks import check_is_owner, check_user_balance

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
# @dev emit insurance payout events, useful for tracking the insolvency of the system over time (monitoring/dashboard)
# all we need to emit is the USDC paid into CZCore, and the insolvency total post pay out
####################################################################################
@event
func event_insurance_payout(payout : felt, insolvency_total : felt):
end

####################################################################################
# @dev view the USDC balance of the insurance fund
# @return 
# - the amount in USDC 
####################################################################################
@view
func insurance_fund_value{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (balance : felt):
    alloc_locals
    let (_trusted_addy) = trusted_addy.read()
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (balance_unit : Uint256) = Erc20.ERC20_balanceOf(usdc_addy, if_addy)
    let (balance_erc) = Math10xx8_fromUint256(balance_unit)
    let (decimals) = Erc20.ERC20_decimals(usdc_addy)
    let (balance) = Math10xx8_convert_to(balance_erc, decimals)
    return(balance)
end

####################################################################################
# @dev this triggers an insurance payout to CZCore
# @dev transfers USDC into CZCore, increases the capital total and decreases the insolvency total in cz state 
# @param input is 
# - the amount in USDC of the payout
####################################################################################
@external
func insurance_fund_payout{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(payout : felt):
    alloc_locals
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    # @dev check that the amount payout is <= the insolvency total else LPs benefiting from IF
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (if_addy) = TrustedAddy.get_if_addy(_trusted_addy)
    let (usdc_addy) = TrustedAddy.get_usdc_addy(_trusted_addy)
    let (lp_total, capital_total, loan_total, insolvency_total, reward_total) = CZCore.get_cz_state(czcore_addy)
    with_attr error_message("Can not payout more than the insolvency total."):
        assert_le(payout, insolvency_total)
    end

    # @dev check that the IF has sufficient USDC reserves to make the payout
    let (payout_erc) = check_user_balance(if_addy, usdc_addy, payout)
    let (payout_unit) = Math10xx8_toUint256(payout_erc)
    Erc20.ERC20_transfer(usdc_addy, czcore_addy, payout_unit)
    # @dev update CZCore
    let (new_capital_total) = Math10xx8_add(capital_total, payout)
    let (new_insolvency_total) = Math10xx8_sub(insolvency_total, payout)
    CZCore.set_cz_state(czcore_addy, lp_total, new_capital_total, loan_total, new_insolvency_total, reward_total)
    # emit event
    event_insurance_payout.emit(payout, new_insolvency_total)
    return()
end
