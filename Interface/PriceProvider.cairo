# PP contract
# all numbers passed into contract must be Math64x61 type

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import (TrustedAddy, CZCore, Settings)
from Math.Math64x61 import (Math64x61_mul, Math64x61_div, Math64x61_sub, Math64x61_add, Math64x61_pow)

##################################################################
# constants 
const Math64x61_FRACT_PART = 2 ** 61
const Math64x61_ONE = 1 * Math64x61_FRACT_PART
const Math64x61_TEN = 10 * Math64x61_FRACT_PART

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
# events keeping tracks of what happened
@event
func pp_token_change(addy : felt, pp_status : felt, lp_change : felt, cz_change : felt):
end

##################################################################
# PP contract functions
# view user PP status
@view
func get_pp_status{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt) -> (lp_token : felt, cz_token : felt, status : felt):
    
    # Obtain the address of the czcore contract
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    
    # check pp status and tokens 
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(czcore_addy,user)
    return (lp_locked,cz_locked,pp_status)
end

# promote user to PP
@external
func set_pp_promote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    
    # Obtain the address of the czcore contract
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(czcore_addy,user)
    
    # check if status not 1 already - existing pp
    with_attr error_message("User is already an existing PP."):
        assert pp_status = 0
    end
    
    # get the current token requirements
    let (settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_require,cz_require) = Settings.get_pp_token_requirement(settings_addy)
    
    # check that user has eno LP tokens
    let (lp_user,lockup) = CZCore.get_lp_balance(czcore_addy,user)
    # verify user has sufficient LP tokens 
    let (temp1) = Math64x61_sub(lp_user, lp_require)
    with_attr error_message("Insufficent lp tokens to promote."):
        assert_nn(temp1)
    end
    
    # transfer the actual CZT tokens to CZCore reserves
    let (cztc_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    
    # get user CZT balance - not Math64x61 types
    let (CZT_user) = CZCore.erc20_balanceOf(czcore_addy, cztc_addy, user)
    let (decimals) = CZCore.erc20_decimals(czcore_addy, cztc_addy)
    
    # do decimal conversion so comparing like with like
    let (temp1) = Math64x61_pow(Math64x61_TEN,decimals)
    let (temp2) = Math64x61_mul(cz_require,temp1)
    let (cz_require_erc) = Math64x61_div(temp2,Math64x61_ONE) 
    
    # Verify that the user has sufficient funds before call
    with_attr error_message("User does not have sufficient funds."):
       assert_le(cz_require_erc, CZT_user)
    enn
    
    # transfer the actual CZT tokens to CZCore reserves - ERC decimal version
    CZCore.erc20_transferFrom(czcore_addy, cztc_addy, user, czcore_addy, cz_require_erc)
        
    # call czcore to promote and update
    CZCore.set_pp_status(czcore_addy,user,lp_user,lp_require,cz_require,lockup,1)
    
    # event
    pp_token_change.emit(addy=user,pp_status=1,lp_change=lp_require,cz_change=cz_require)  
    return()
end

# demote user from PP
@external
func set_pp_demote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():

    # Obtain the address of the czcore contract
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(czcore_addy,user)
    
    # check if status not 0 already - not a pp
    with_attr error_message("User is not an existing PP."):
        assert pp_status = 1
    end
    
    # transfer the actual CZT tokens to CZCore reserves
    let (cztc_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    
    # cz_locked - is a Math64x61 type
    let (decimals) = CZCore.erc20_decimals(czcore_addy, cztc_addy)
    
    # do decimal conversion so comparing like with like
    let (temp1) = Math64x61_pow(Math64x61_TEN,decimals)
    let (temp2) = Math64x61_mul(cz_locked,temp1)
    let (cz_locked_erc) = Math64x61_div(temp2,Math64x61_ONE) 
    
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
