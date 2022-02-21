# PP contract
# all numbers passed into contract must be Math64x61 type

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le
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
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(deployer : felt):
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
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
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
# need to emit PP events so that we can do reporting / dashboard to monitor system
# need to emit amount of lp and cz change, to recon vs. total lp cz holdings for pp
@event
func pp_token_change(addy : felt, pp_status : felt, lp_change : felt, cz_change : felt):
end

##################################################################
# PP contract functions
# view user PP status
@view
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt) -> (lp_token : felt, cz_token : felt, status : felt):
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(czcore_addy,user)
    return (lp_locked,cz_locked,pp_status)
end

# promote user to PP
@external
func set_pp_promote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    
    # check if status not 1 already - existing pp
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(czcore_addy,user)
    with_attr error_message("User is already an existing PP."):
        assert pp_status = 0
    end
    
    # check that user has eno LP tokens
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_require,cz_require) = Settings.get_pp_token_requirement(settings_addy)    
    let (lp_user,lockup) = CZCore.get_lp_balance(czcore_addy,user)
    with_attr error_message("Insufficent lp tokens to promote."):
        assert_nn_le(lp_require,lp_user)
    end
    
    # Verify that the user has sufficient funds before call
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_user) = ERC20.ERC20_balanceOf(czt_addy, user)
    let (czt_decimals) = ERC20.ERC20_decimals(czt_addy)
    # do decimal conversion so comparing like with like
    let (cz_require_erc) = Math64x61_convert_from(czt_require, czt_decimals)
    with_attr error_message("User does not have sufficient funds."):
       assert_le(cz_require_erc, czt_user)
    enn
    
    # transfer the actual CZT tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, czt_addy, user, czcore_addy, cz_require_erc)
    # call czcore to promote and update
    CZCore.set_pp_status(czcore_addy,user,lp_user,lp_require,cz_require,lockup,1)
    # event
    pp_token_change.emit(addy=user,pp_status=1,lp_change=lp_require,cz_change=cz_require)  
    return()
end

# demote user from PP
@external
func set_pp_demote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():

    # check if status not 0 already - not a pp
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(czcore_addy,user)
    with_attr error_message("User is not an existing PP."):
        assert pp_status = 1
    end
    
    # transfer the actual CZT tokens to CZCore reserves
    let (czt_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    let (czt_decimals) = ERC20.ERC20_decimals(czt_addy)
    # do decimal conversion so comparing like with like
    let (cz_locked_erc) = Math64x61_convert_from(cz_locked, czt_decimals)
    
    # transfer the actual CZT tokens from CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, cztc_addy, czcore_addy, user, cz_locked_erc)
    # get user lp balance
    let (lp_user,lockup) = CZCore.get_lp_balance(czcore_addy,user)
    # call czcore to demote and update
    CZCore.set_pp_status(czcore_addy,user,lp_user,lp_locked,cz_locked,lockup,0)
    # event
    pp_token_change.emit(addy=user,pp_status=0,lp_change=lp_locked,cz_change=cz_locked)  
    return()
end
