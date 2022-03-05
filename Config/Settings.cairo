# Settings contract
# all numbers stored / passed into contract must be Math10xx6 type

# imports
%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import (TrustedAddy)
from Functions.Math10xx8 import Math10xx8_add

##################################################################
# constants 
const Math10xx8_FRACT_PART = 10 ** 8
const Math10xx8_ONE = 1 * Math10xx8_FRACT_PART
const origination_fee_total = 100000
const origination_fee_split = 50000000
const accrued_interest_split_1 = 95000000
const accrued_interest_split_2 = 3000000
const accrued_interest_split_3 = 2000000
const utilization_total = 90000000
const insurance_shortfall = 1000000
const ltv = 60000000

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
    pp_token_requirement.write((1000 * Math10xx8_ONE, 1000 * Math10xx8_ONE))
    # 7 day lockup period
    lockup_period.write(0 * 604800 * Math10xx8_ONE)
    # origination fee and split 10bps and 50/50 PP IF
    origination_fee.write((origination_fee_total, origination_fee_split, origination_fee_split))
    # accrued interest split between LP IF and GT - 95/3/2
    accrued_interest_split.write((accrued_interest_split_1, accrued_interest_split_2, accrued_interest_split_3))
    # min loan and max loan amounts
    min_max_loan.write((10**2*Math10xx8_ONE - 1, 10**4*Math10xx8_ONE + 1))
    # min deposit and max deposit from LPs accepted
    min_max_deposit.write((10**2*Math10xx8_ONE - 1, 10**4*Math10xx8_ONE + 1))
    # utilization start and stop levels
    utilization.write(utilization_total)
    # min number of PPs for pricing
    min_pp_accepted.write(1*Math10xx8_ONE)
    # insurance shortfall ratio to lp capital
    insurance_shortfall_ratio.write(insurance_shortfall)    
    # max loan term - 1 year initially
    max_loan_term.write(366 * 86400 * Math10xx8_ONE)   
    # weth ltv
    weth_ltv.write(ltv)  
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
    let (temp1) = Math10xx8_add(pp_split,if_split)
    with_attr error_message("PP split and IF split should sum to 1"):
        assert temp1 = Math10xx8_ONE
    end
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
    let (temp1) = Math10xx8_add(lp_split,if_split)
    let (temp2) = Math10xx8_add(temp1,gt_split)
    with_attr error_message("LP split and IF split and GT split should sum to 1"):
        assert temp2 = Math10xx8_ONE
    end
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
# min deposit and max deposit from LPs accepted
@storage_var
func min_max_deposit() -> (res : (felt,felt)):
end

# return min deposit and max deposit from LPs accepted
@view
func get_min_max_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (min_deposit : felt, max_deposit : felt):
    let (res) = min_max_deposit.read()
    return (res[0],res[1])
end

# set min deposit and max deposit from LPs accepted
@external
func set_min_max_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_deposit : felt, max_deposit : felt):
    check_caller_is_controller()
    min_max_deposit.write((min_deposit,max_deposit))
    return ()
end

##################################################################
# utilization start and stop levels
@storage_var
func utilization() -> (res : felt):
end

# return stop utilization level
@view
func get_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (stop : felt):
    let (res) = utilization.read()
    return (res)
end

# set stop utilization level for loan provision
@external
func set_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stop : felt):
    check_caller_is_controller()
    utilization.write(stop)
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
func get_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (is_ratio : felt):
    let (res) = insurance_shortfall_ratio.read()
    return (res)
end

# set insurance shortfall ratio to lp capital
@external
func set_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(is_ratio : felt):
    check_caller_is_controller()
    insurance_shortfall_ratio.write(is_ratio)
    return ()
end

##################################################################
# max loan term
@storage_var
func max_loan_term() -> (res : felt):
end

# return max loan term
@view
func get_max_loan_term{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (max_term : felt):
    let (res) = max_loan_term.read()
    return (res)
end

# set max loan term
@external
func set_max_loan_term{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(max_term : felt):
    check_caller_is_controller()
    max_loan_term.write(max_term)
    return ()
end

##################################################################
# weth ltv
@storage_var
func weth_ltv() -> (res : felt):
end

# return weth ltv
@view
func get_weth_ltv{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (ltv : felt):
    let (res) = weth_ltv.read()
    return (res)
end

# set weth ltv
@external
func set_weth_ltv{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(ltv : felt):
    check_caller_is_controller()
    weth_ltv.write(ltv)
    return ()
end
