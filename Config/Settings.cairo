# Settings contract

# imports
%lang starknet
%builtins pedersen range_check
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import (TrustedAddy)

##################################################################
# addy of the deployer
@storage_var
func deployer_addy() -> (addy : felt):
end

# set the addy of the delpoyer on deploy 
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(deployer : felt):
    deployer_addy.write(deployer)
    # set initial amounts for becoming pp - NB NB change this later
    pp_token_requirement.write((5000,5000))
    # 7 day lockup period
    lockup_period.write(604800)
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
# check caller is controller
func check_caller_is_controller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (_trusted_addy) = trusted_addy.read()
    let (_controller_addy) = TrustedAddy.get_controller_addy(_trusted_addy)
    with_attr error_message("Not authorised caller."):
        assert caller = _controller_addy
    end
    return ()
end

##################################################################
# functions to set the amount of LP CZ tokens needed to become a PP
@storage_var
func pp_token_requirement() -> (require : (felt, felt)):
end

# returns the current requirement to become PP
@view
func get_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lp_require : felt, cz_require : felt):
    let (res) = pp_token_requirement.read()
    return (res[0],res[1])
end

# set new token requirement to become PP
@external
func set_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_require : felt, cz_require : felt):
    check_caller_is_controller()
    pp_token_requirement.write((lp_require,cz_require))
    return ()
end

##################################################################
# lock up period for both LP capital in/out and GT stake/unstake
@storage_var
func lockup_period() -> (lockup : felt):
end

# returns the current requirement to become PP
@view
func get_lockup_period{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lockup : felt):
    let (res) = lockup_period.read()
    return (res)
end

# set new lockup period
@external
func set_lockup_period{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lockup : felt):
    check_caller_is_controller()
    lockup_period.write(lockup)
    return ()
end

##################################################################
# origination fee and split btw PP and IF
@storage_var
func origination_fee() -> (res : (felt,felt,felt)):
end

# return origination fee and split
@view
func get_origination_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (fee : felt, pp_split : felt, if_split : felt):
    let (res) = origination_fee.read()
    return (res[0],res[1],res[2])
end

# set origination fee and split
@external
func set_origination_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt, pp_split : felt, if_split : felt):
    check_caller_is_controller()
    origination_fee.write((fee,pp_split,if_split))
    return ()
end

##################################################################
# accrued interest split between LP IF and GT
@storage_var
func accrued_interest_split() -> (res : (felt,felt,felt)):
end

# return accrued interest splits
@view
func get_accrued_interest_split{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lp_split : felt, if_split : felt, gt_split : felt):
    let (res) = accrued_interest_split.read()
    return (res[0],res[1],res[2])
end

# set accrued interest splits
@external
func set_accrued_interest_split{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_split : felt, if_split : felt, gt_split : felt):
    check_caller_is_controller()
    accrued_interest_split.write((lp_split,if_split,gt_split))
    return ()
end

##################################################################
# min loan and max loan amounts
@storage_var
func min_max_loan() -> (res : (felt,felt)):
end

# return min and max allowable loan size
@view
func get_min_max_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (min_loan : felt, max_loan : felt):
    let (res) = min_max_loan.read()
    return (res[0],res[1])
end

# set min and max loan size
@external
func set_min_max_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_loan : felt, max_loan : felt):
    check_caller_is_controller()
    min_max_loan.write((min_loan,max_loan))
    return ()
end

##################################################################
# utilization start and stop levels
@storage_var
func utilization() -> (res : (felt,felt)):
end

# return start and stop utilization levels
@view
func get_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (start : felt, stop : felt):
    let (res) = utilization.read()
    return (res[0],res[1])
end

# set start and stop utilization levels for loan provision
@external
func set_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(start : felt, stop : felt):
    check_caller_is_controller()
    utilization.write((start,stop))
    return ()
end

##################################################################
# min number of PPs for pricing
@storage_var
func min_pp_accepted() -> (res : felt):
end

# return min number of PPs for pricing request
@view
func get_min_pp_accepted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (min_pp : felt):
    let (res) = min_pp_accepted.read()
    return (res)
end

# set min PP required for acceptable pricing request
@external
func set_min_pp_accepted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_pp : felt):
    check_caller_is_controller()
    min_pp_accepted.write(min_pp)
    return ()
end

##################################################################
# insurance shortfall ratio to lp capital
@storage_var
func insurance_shortfall_ratio() -> (res : felt):
end

# return insurance shortfall ratio to lp capital
@view
func get_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (insurance_shortfall_ratio : felt):
    let (res) = insurance_shortfall_ratio.read()
    return (res)
end

# set insurance shortfall ratio to lp capital
@external
func set_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(insurance_shortfall_ratio : felt):
    check_caller_is_controller()
    insurance_shortfall_ratio.write(min_pp)
    return ()
end
