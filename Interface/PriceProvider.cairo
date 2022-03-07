####################################################################################
# @title PriceProvider contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - view their current status to see if they are a valid pricing provider
# - promote themselves to become a pricing provider by locking both LP and CZT (native curvezero) tokens
# - demote themselves from pricing provider and uplocking both their LP and CZT tokens
# Princing provider LP and CZT token requirements are stored in Settings contract and can be updated by controller
# This contract addy will be stored in the TrustedAddy contract
# This contract talks directly to the CZCore contract
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
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
# @dev emit PP events for reporting / dashboard to monitor system
# TODO check that this reports correctly for negative / reductions
####################################################################################
@event
func event_pp_status(addy : felt, pp_status : felt, lp_change : felt, czt_change : felt):
end

####################################################################################
# @dev this allows a user to view their pricing provider status
# @param input is the user addy
# @return 
# - number of lp tokens locked up
# - number of CZT tokens locked up
# - users current pricing provider status 0 - not pp 1 - valid pp
####################################################################################
@view
func view_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt) -> (lp_token : felt, czt_token : felt, status : felt):
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    return (lp_locked, czt_locked, pp_status)
end

####################################################################################
# @dev this allows a user to promote themselves to a pricing provider
# user must have the min LP and CZT tokens per the requirement in Settings contract
####################################################################################
@external
func promote_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    alloc_locals
    # @dev check if status not 1 already - existing pp
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    with_attr error_message("User is already an existing PP."):
        assert pp_status = 0
    end
    
    # @dev check that user has eno LP tokens
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_require, czt_require) = Settings.get_pp_token_requirement(settings_addy)    
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    with_attr error_message("Insufficent lp tokens to promote."):
        assert_nn_le(lp_require, lp_user)
    end
    
    # @dev check that user has eno CZT tokens
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_require_erc) = check_user_balance(user, czt_addy, czt_require)
    # @dev transfer the CZT, promote PP
    CZCore.erc20_transferFrom(czcore_addy, czt_addy, user, czcore_addy, czt_require_erc)
    CZCore.set_pp_status(czcore_addy, user, lp_user, lp_require, czt_require, lockup, 1)
    # @dev emit event
    event_pp_status.emit(addy=user, pp_status=1, lp_change=lp_require, czt_change=czt_require)  
    return()
end

####################################################################################
# @dev this allows a user to demote themselves from a pricing provider and unlock their tokens
# user unlock will be the tokens they locked at the time and not the current requirement in Settings contract
####################################################################################
@external
func demote_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    alloc_locals
    # @dev check if status not 0 already - not a pp
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    with_attr error_message("User is not an existing PP."):
        assert pp_status = 1
    end
    
    # @dev check that czcore has eno CZT tokens
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_locked_erc) = check_user_balance(czcore_addy, czt_addy, czt_locked)

    # @dev transfer the CZT, demote PP
    CZCore.erc20_transfer(czcore_addy, czt_addy, user, czt_locked_erc)
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    CZCore.set_pp_status(czcore_addy, user, lp_user, lp_locked, czt_locked, lockup, 0)
    # @dev emit event
    event_pp_status.emit(addy=user, pp_status=0, lp_change=lp_locked, czt_change=czt_locked)  
    return()
end
