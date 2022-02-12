# PP contract

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn, assert_nn_le, unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import (TrustedAddy,CZCore,Setttings)

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
    let (_czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    
    # check pp status and tokens 
    let (_pp_status) = CZCore.get_pp_status(_czcore_addy,user)
    return (_pp_status)
end

# promote user to PP
@external
func set_pp_promote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    
    # Obtain the address of the czcore contract
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (_czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(_czcore_addy,user)
    
    # check if status not 1 already - existing pp
    with_attr error_message("User is already an existing PP."):
        assert _pp_status = 0
    end
    
    # get the current token requirements
    let (_settings_addy) = TrustedAddy.get_settings_addy(_trusted_addy)
    let (lp_require,cz_require) = Setttings.get_pp_token_requirement()
    
    # check that user has eno LP tokens
    let (lp_user) = CZCore.get_lp_balance(_czcore_addy,user)
    # verify user has sufficient LP tokens 
    with_attr error_message("Insufficent lp tokens to promote."):
        assert_nn(lp_user-lp_require)
    end
    
    # transfer the actual CZT tokens to CZCore reserves
	let (_cztc_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    CZCore.erc20_transferFrom(_czcore_addy, _cztc_addy, user, _czcore_addy, cz_require)
        
    # call czcore to promote and update
    CZCore.set_pp_promote(_czcore_addy,user,lp_user,lp_require,cz_require):
    return()
end

# demote user from PP
func set_pp_demote{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(user : felt):

    # Obtain the address of the czcore contract
    let (user) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (_czcore_addy) = TrustedAddy.get_czcore_addy(_trusted_addy)
    let (lp_locked,cz_locked,pp_status) = CZCore.get_pp_status(_czcore_addy,user)
    
    # check if status not 0 already - not a pp
    with_attr error_message("User is not an existing PP."):
        assert pp_status = 1
    end
    
    # transfer the actual CZT tokens to CZCore reserves
	let (_cztc_addy) = TrustedAddy.get_czt_addy(_trusted_addy)
    CZCore.erc20_transferFrom(_czcore_addy, _cztc_addy, _czcore_addy, user, cz_locked)
        
    # get user lp balance
    let (lp_user) = CZCore.get_lp_balance(_czcore_addy,user)
    
    # call czcore to demote and update
    CZCore.set_pp_demote(_czcore_addy,user,lp_user,lp_locked):
    return()
end
