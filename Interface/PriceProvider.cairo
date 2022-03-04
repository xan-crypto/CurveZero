# PP contract
# all numbers passed into contract must be Math64x61 type
# events include event_pp_status
# functions include view_pp_status, promote_pp_status, demote_pp_status

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math64x61 import Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add, Math64x61_convert_from
from Functions.Checks import check_is_owner, check_user_balance

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
# emit PP events for reporting / dashboard to monitor system
@event
func event_pp_status(addy : felt, pp_status : felt, lp_change : felt, czt_change : felt):
end

##################################################################
# view the PP status of a user
@view
func view_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt) -> (lp_token : felt, czt_token : felt, status : felt):
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    return (lp_locked, czt_locked, pp_status)
end

# promote user to PP
@external
func promote_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    alloc_locals
    # check if status not 1 already - existing pp
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    with_attr error_message("User is already an existing PP."):
        assert pp_status = 0
    end
    
    # check that user has eno LP tokens
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_require, czt_require) = Settings.get_pp_token_requirement(settings_addy)    
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    with_attr error_message("Insufficent lp tokens to promote."):
        assert_nn_le(lp_require, lp_user)
    end
    
    # check that user has eno CZT tokens
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_require_erc) = check_user_balance(user, czt_addy, czt_require)
    # transfer the CZT, promote PP
    CZCore.erc20_transferFrom(czcore_addy, czt_addy, user, czcore_addy, czt_require_erc)
    CZCore.set_pp_status(czcore_addy, user, lp_user, lp_require, czt_require, lockup, 1)
    # event
    event_pp_status.emit(addy=user, pp_status=1, lp_change=lp_require, czt_change=czt_require)  
    return()
end

# demote user from PP
@external
func demote_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    alloc_locals
    # check if status not 0 already - not a pp
    let (_trusted_addy) = trusted_addy.read()
    let (user) = get_caller_address()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked, czt_locked, pp_status) = CZCore.get_pp_status(czcore_addy, user)
    with_attr error_message("User is not an existing PP."):
        assert pp_status = 1
    end
    
    # check that czcore has eno CZT tokens
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_locked_erc) = check_user_balance(czcore_addy, czt_addy, czt_locked)

    # transfer the CZT, demote PP
    CZCore.erc20_transfer(czcore_addy, czt_addy, czcore_addy, user, czt_locked_erc)
    let (lp_user, lockup) = CZCore.get_lp_balance(czcore_addy, user)
    CZCore.set_pp_status(czcore_addy, user, lp_user, lp_locked, czt_locked, lockup, 0)
    # event
    event_pp_status.emit(addy=user, pp_status=0, lp_change=lp_locked, czt_change=czt_locked)  
    return()
end
