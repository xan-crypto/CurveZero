####################################################################################
# @title Settings contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - view the owner addy
# - view the TrustedAddy contract address where all contract addys are stored
# - view the token requirements to become a PP
# - view the lockup for a PP post valid price submission
# - view loan origination fee and split between PP/IF
# - view accrued interest split between LP/IF/GT
# - view the min max loan in USDC
# - view the min max deposit in USDC for LP tokens
# - view the utilization stop level, after which no new loans will be granted
# - view the min number of PP for valid pricing 
# - view the insurance shortfall ratio, beyond which LP/GT changes are locked pending resolution
# - view the min max loan term
# - view the WETH ltv for loan creation
# - view the WETH liquidation ratio for loan liquidation
# - view the WETH liquidation fee
# - view the grace period, period after end ts that a loan is liquidated
# - view the pp slash percentage
# - view the lp yield boost (this is a fixed spread over the pp oracle median to balance supply/demand)
# Owner can set all of the above (excluding the owner addy), with defaults set on initialization 
# Owner will be the same addy as the controller and will be a multisig wallet 
# This contract addy will be stored in the TrustedAddy contract
# This contract responds to all contracts but listens to changes from owner only
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math_cmp import is_in_range
from InterfaceAll import TrustedAddy
from Functions.Math10xx8 import Math10xx8_add, Math10xx8_one
from Functions.Checks import check_is_owner

####################################################################################
# @dev constants for the constructor
# Number are all in Math10xx8 format
####################################################################################
const Math10xx8_FRACT_PART = 10 ** 8
const Math10xx8_ONE = 1 * Math10xx8_FRACT_PART
const origination_fee_total = 200000
const origination_fee_split = 50000000
const accrued_interest_split_1 = 90000000
const accrued_interest_split_2 = 5000000
const accrued_interest_split_3 = 5000000
const utilization_total = 90000000
const insurance_shortfall = 1000000
const ltv = 60000000
const liquidation_rato = 110000000
const liquidation_fee = 2500000
const liquidation_period = 60480000000000
const pp_slash_amount = 50000000
const pp_lockup_period = 60480000000000
const lp_yield_spread = 1000000
const max_lp_yield_spread = 10000000

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
# this allows for upgradability of this contract
####################################################################################
@storage_var
func owner_addy() -> (addy : felt):
end

@view
func get_owner_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = owner_addy.read()
    return (addy)
end

@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(owner : felt):
    owner_addy.write(owner)
    # @dev set initial amounts for becoming pp - NB NB change this later
    pp_token_requirement.write((1000 * Math10xx8_ONE, 1000 * Math10xx8_ONE))
    # @dev set initial lock up period post of valid pricing request
    pp_lockup.write(pp_lockup_period)
    # @dev origination fee and split 20bps and 50/50 PP IF
    origination_fee.write((origination_fee_total, origination_fee_split, origination_fee_split))
    # @dev accrued interest split between LP IF and GT - 90/5/5
    accrued_interest_split.write((accrued_interest_split_1, accrued_interest_split_2, accrued_interest_split_3))
    # @dev min loan and max loan amounts
    min_max_loan.write((10**2*Math10xx8_ONE - 1, 10**4*Math10xx8_ONE + 1))
    # @dev min deposit and max deposit from LPs accepted
    min_max_deposit.write((10**2*Math10xx8_ONE - 1, 10**4*Math10xx8_ONE + 1))
    # @dev utilization start and stop levels
    utilization.write(utilization_total)
    # @dev min number of PPs for pricing
    min_pp_accepted.write(1*Math10xx8_ONE)
    # @dev insurance shortfall ratio to lp capital
    insurance_shortfall_ratio.write(insurance_shortfall)    
    # @dev max loan term - 3 months initially
    max_loan_term.write(92 * 86400 * Math10xx8_ONE)   
    # @dev weth ltv
    weth_ltv.write(ltv)  
    # @dev weth liquidation ratio
    weth_liquidation_ratio.write(liquidation_rato)  
    # @dev liquidation fee
    weth_liquidation_fee.write(liquidation_fee)  
    # @dev liquidation settlement period
    grace_period.write(liquidation_period)
    # @dev pp slash percentage
    pp_slash_percentage.write(pp_slash_amount)
    # @dev lp yield boost / spread
    lp_yield_boost.write(lp_yield_spread)    
    return ()
end

####################################################################################
# @dev storage for the trusted addy contract
# the TrustedAddy contract stores all the contract addys
####################################################################################
@storage_var
func trusted_addy() -> (addy : felt):
end

@view
func get_trusted_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
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
# @dev view / set current requirement to become PP
# Locking up LP and CZT tokens aligns PP with the protocol, malicious activity can result in slashing
# @param / @return 
# - Lp tokens required
# - CZT tokens required
####################################################################################
@storage_var
func pp_token_requirement() -> (require : (felt, felt)):
end

@view
func get_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lp_require : felt, cz_require : felt):
    let (res) = pp_token_requirement.read()
    return (res[0],res[1])
end

@external
func set_pp_token_requirement{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_require : felt, cz_require : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    pp_token_requirement.write((lp_require,cz_require))
    return ()
end

####################################################################################
# @dev view / set lockup period for PP post valid pricing request
# Locking up LP and CZT tokens aligns PP with the protocol, malicious activity can result in slashing 
# Governance has the lock up period to decide on whether slashing is appropriate
# @param / @return 
# - lock up period
####################################################################################
@storage_var
func pp_lockup() -> (lockup : felt):
end

@view
func get_pp_lockup{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lockup : felt):
    let (res) = pp_lockup.read()
    return (res)
end

@external
func set_pp_lockup{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lockup : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    pp_lockup.write(lockup)
    return ()
end

####################################################################################
# @dev view / set origination fee and split btw PP and IF
# @param / @return 
# - fee in % and in Math10xx8 20bps = 0.002 * 10**8
# - PP split
# - IF split
####################################################################################
@storage_var
func origination_fee() -> (res : (felt,felt,felt)):
end

@view
func get_origination_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (fee : felt, pp_split : felt, if_split : felt):
    let (res) = origination_fee.read()
    return (res[0],res[1],res[2])
end

@external
func set_origination_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt, pp_split : felt, if_split : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    let (sum_splits) = Math10xx8_add(pp_split,if_split)
    with_attr error_message("PP split and IF split should sum to 1"):
        assert sum_splits = Math10xx8_ONE
    end
    origination_fee.write((fee,pp_split,if_split))
    return ()
end

####################################################################################
# @dev view / set accrued interest split between LP IF and GT
# accrued interest is rewarded to below only on full loan repayment
# splits should sum to 1
# @param / @return 
# - LP split
# - IF split
# - GT split
####################################################################################
@storage_var
func accrued_interest_split() -> (res : (felt,felt,felt)):
end

@view
func get_accrued_interest_split{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lp_split : felt, if_split : felt, gt_split : felt):
    let (res) = accrued_interest_split.read()
    return (res[0],res[1],res[2])
end

@external
func set_accrued_interest_split{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_split : felt, if_split : felt, gt_split : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    let (sum_partial) = Math10xx8_add(lp_split,if_split)
    let (sum_full) = Math10xx8_add(sum_partial,gt_split)
    with_attr error_message("LP split and IF split and GT split should sum to 1"):
        assert sum_full = Math10xx8_ONE
    end
    accrued_interest_split.write((lp_split,if_split,gt_split))
    return ()
end

####################################################################################
# @dev view / set min loan and max loan amounts
# loan size might be limited to reduce risk
# @param / @return 
# - min loan
# - max loan
####################################################################################
@storage_var
func min_max_loan() -> (res : (felt,felt)):
end

@view
func get_min_max_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (min_loan : felt, max_loan : felt):
    let (res) = min_max_loan.read()
    return (res[0],res[1])
end

@external
func set_min_max_loan{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_loan : felt, max_loan : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    min_max_loan.write((min_loan,max_loan))
    return ()
end

####################################################################################
# @dev view / set min deposit and max deposit from LPs accepted
# deposits size might be limited to reduce risk
# @param / @return 
# - min deposit
# - max deposit
####################################################################################
@storage_var
func min_max_deposit() -> (res : (felt,felt)):
end

@view
func get_min_max_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (min_deposit : felt, max_deposit : felt):
    let (res) = min_max_deposit.read()
    return (res[0],res[1])
end

@external
func set_min_max_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_deposit : felt, max_deposit : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    min_max_deposit.write((min_deposit,max_deposit))
    return ()
end

####################################################################################
# @dev view / set utilization stop levels
# we need to keep a utilization level stop so that a capital buffer is kept for LP withdrawals
# if a new loan / refinance loan could breach this utilization level, the loan is rejected
# @param / @return 
# - stop level - set to 90% initially
####################################################################################
@storage_var
func utilization() -> (res : felt):
end

@view
func get_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (stop : felt):
    let (res) = utilization.read()
    return (res)
end

@external
func set_utilization{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(stop : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    utilization.write(stop)
    return ()
end

####################################################################################
# @dev view / set min number of PPs for pricing
# pricing oracles need atleast some min number of submission for the price to be accurate
# if have 101 PP prices then 50 can be malcious on a pricing request and we still get reasonable price (median based)
# PP that price will have stakes locked for 7 day for slashing if needed
# @param / @return 
# - min number of PP submission for a valid price
####################################################################################
@storage_var
func min_pp_accepted() -> (res : felt):
end

@view
func get_min_pp_accepted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (min_pp : felt):
    let (res) = min_pp_accepted.read()
    return (res)
end

@external
func set_min_pp_accepted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(min_pp : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    min_pp_accepted.write(min_pp)
    return ()
end

####################################################################################
# @dev view / set insurance shortfall ratio to lp capital
# in the event of loan insolvency we need an immediate way to prevent LPs/GTs from leaving the system
# recall that GTs can be slashed to bridge the liquidity gap, the insurance shortfall will prevent LP/GT leaving if liquidity gap in system
# this gives time to the controller to call pause and then use IF funds, then GT funds, then LP haircut if needed to bridge
# @param / @return 
# - insolvency ratio minimum
# this is compared to the the current insolvency ratio - the insolvency total divided by the Capital total in CZCore
####################################################################################
@storage_var
func insurance_shortfall_ratio() -> (res : felt):
end

@view
func get_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (is_ratio : felt):
    let (res) = insurance_shortfall_ratio.read()
    return (res)
end

@external
func set_insurance_shortfall_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(is_ratio : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    insurance_shortfall_ratio.write(is_ratio)
    return ()
end

####################################################################################
# @dev view / set max loan term
# this is to reduce risk, by only pricing/accepting loans that are less than x years for example
# @param / @return 
# - max loan term in seconds and in Math10xx8
####################################################################################
@storage_var
func max_loan_term() -> (res : felt):
end

@view
func get_max_loan_term{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (max_term : felt):
    let (res) = max_loan_term.read()
    return (res)
end

@external
func set_max_loan_term{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(max_term : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    max_loan_term.write(max_term)
    return ()
end

####################################################################################
# @dev view / set WETH ltv
# this is the loan you can take given your WETH collateral
# e.g. at 0.6 in Math10xx8 for every 1000 USD of WETH collateral you can only take a loan of 600 USDC max
# @param / @return 
# - WETH ltv
####################################################################################
@storage_var
func weth_ltv() -> (res : felt):
end

@view
func get_weth_ltv{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (ltv : felt):
    let (res) = weth_ltv.read()
    return (res)
end

@external
func set_weth_ltv{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(ltv : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    weth_ltv.write(ltv)
    return ()
end

####################################################################################
# @dev view / set WETH liquidation ratio
# this is the amount below which a loan can be liquidated by a loan liquidator
# e.g. at 110% -> 1.1 in Math10xx8, we take the accrued notional x 1.1 and if the collateral value is below this
# then any one can call liquidate on the loan in return for a fee
# @param / @return 
# - WETH liquidation ratio
####################################################################################
@storage_var
func weth_liquidation_ratio() -> (res : felt):
end

@view
func get_weth_liquidation_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (ratio : felt):
    let (res) = weth_liquidation_ratio.read()
    return (res)
end

@external
func set_weth_liquidation_ratio{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(ratio : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    weth_liquidation_ratio.write(ratio)
    return ()
end

####################################################################################
# @dev view / set liquidation fee
# this is the fee that the loan liquidator earns from liquidating the loan
# initially this fee will be set at 2.5%, so $25 on a $1000 liquidation
# @param / @return 
# - liquidation fee
####################################################################################
@storage_var
func weth_liquidation_fee() -> (res : felt):
end

@view
func get_weth_liquidation_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (fee : felt):
    let (res) = weth_liquidation_fee.read()
    return (res)
end

@external
func set_weth_liquidation_fee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    weth_liquidation_fee.write(fee)
    return ()
end

####################################################################################
# @dev view / set grace period post end of loan 
# if a user does not repay the loan at maturity, we wait 7 days and then liquidate the loan
# the grace period thus ensures that capital is recycled
# it also prevents an attack vector where someone borrows for 1wk to get a low rate and then keeps the loan open for 5 years
# this would effectively be a way to arbitrage the system
# @param / @return 
# - period
####################################################################################
@storage_var
func grace_period() -> (res : felt):
end

@view
func get_grace_period{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (period : felt):
    let (res) = grace_period.read()
    return (res)
end

@external
func set_grace_period{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(period : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    grace_period.write(period)
    return ()
end

####################################################################################
# @dev view / set the PP slash percentage
# this is the amount of LP and CZT tokens that are taken from the PP if slashed
# slashing will occur if there is some malicious behaviour and is called by controller
# @param / @return 
# - slash
####################################################################################
@storage_var
func pp_slash_percentage() -> (res : felt):
end

@view
func get_pp_slash_percentage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (percentage : felt):
    let (res) = pp_slash_percentage.read()
    return (res)
end

@external
func set_pp_slash_percentage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(percentage : felt):
    alloc_locals
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    let (one) = Math10xx8_one()
    let (test_range) = is_in_range(percentage, 0, one)
    with_attr error_message("Slash perecent not in required range."):
        assert test_range = 1
    end
    pp_slash_percentage.write(percentage)
    return ()
end

####################################################################################
# @dev view / set the LP yield boost / spread
# this is the spread that gets added on top of the PP oracle curve
# we use this to balance supply and demand, we believe that attracting LP capital initially might be difficult
# thus goverance has the ability to shift this spread higher, making it more attract for LPs to depo capital
# the range for the spread is hard fixed from 0-10%
# @param / @return 
# - lp yield boost
####################################################################################
@storage_var
func lp_yield_boost() -> (res : felt):
end

@view
func get_lp_yield_boost{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (spread : felt):
    let (res) = lp_yield_boost.read()
    return (res)
end

@external
func set_lp_yield_boost{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(spread : felt):
    alloc_locals
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    let (test_range) = is_in_range(spread, 0, max_lp_yield_spread)
    with_attr error_message("Yield boost spread not in required range."):
        assert test_range = 1
    end
    lp_yield_boost.write(spread)
    return ()
end
