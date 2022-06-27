####################################################################################
# @title InterfaceAll contract
# @dev put all interfaces here
# Interfaces include
# - TrustedAddy
# - CZCore
# - Controller
# - Erc20
# - Settings
# - Oracle
# - CapitalBorrower
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.uint256 import (Uint256)

# @dev interface to trusted addy contract
@contract_interface
namespace TrustedAddy:
    func get_lp_addy() -> (addy : felt):
    end
    func get_pp_addy() -> (addy : felt):
    end
    func get_cb_addy() -> (addy : felt):
    end
    func get_ll_addy() -> (addy : felt):
    end
    func get_gt_addy() -> (addy : felt):
    end
    func get_if_addy() -> (addy : felt):
    end
    func get_df_addy() -> (addy : felt):
    end    
    func get_czcore_addy() -> (addy : felt):
    end
    func get_controller_addy() -> (addy : felt):
    end
    func get_settings_addy() -> (addy : felt):
    end
    func get_usdc_addy() -> (addy : felt):
    end
    func get_weth_addy() -> (addy : felt):
    end
    func get_lpt_addy() -> (addy : felt):
    end
    func get_czt_addy() -> (addy : felt):
    end
    func get_oracle_addy() -> (addy : felt):
    end
end

# @dev interfaces to CZCore contract
@contract_interface
namespace CZCore:
    func erc20_transferFrom(erc_addy : felt, sender : felt, recipient : felt, amount : felt):
    end
    func erc20_transfer(erc_addy : felt, recipient : felt, amount : felt):
    end
    func erc20_mint(erc_addy : felt, recipient : felt, amount : felt):
    end
    func erc20_burn(erc_addy : felt, account : felt, amount : felt):
    end   
    func get_accrued_interest() -> (accrued_interest_total : felt, wt_avg_rate : felt, last_accrual_ts : felt):
    end
    func set_update_accrual() -> (accrued_interest_total : felt):
    end
    func set_update_rate(new_loan : felt, new_rate : felt, add_remove : felt) -> ():
    end
    func set_reduce_accrual(payment : felt) -> ():
    end
    func get_cz_state() -> (lp_total : felt, capital_total : felt, loan_total : felt, insolvency_total : felt, reward_total : felt):
    end
    func set_cz_state(lp_total : felt, capital_total : felt, loan_total : felt, insolvency_total : felt, reward_total : felt):
    end 
    func get_pp_status(user : felt) -> (lp_locked : felt, cz_locked : felt, lock_ts : felt, last_id : felt, status : felt):
    end
    func set_pp_status(user : felt, lp_locked : felt, cz_locked : felt, lock_ts : felt, last_id : felt, status : felt):
    end  
    func get_cb_loan(user : felt) -> (notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt):
    end  
    func set_cb_loan(user : felt, notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt, type : felt):
    end  
    func get_staker_index(index : felt) -> (user : felt):
    end  
    func set_staker_index(index : felt, user : felt):
    end  
    func get_staker_details(user : felt) -> (gt_token : felt, unclaimed_reward : felt, old_user : felt):
    end  
    func set_staker_details(user : felt, gt_token : felt, unclaimed_reward : felt):
    end  
    func get_staker_total() -> (stake_total : felt, index : felt):
    end  
    func set_staker_total(stake_total : felt, index : felt):
    end  
end

# @dev interface to controller contract
@contract_interface
namespace Controller:
    func get_paused() -> (addy : felt):
    end
end

# @dev need interface to the ERC-20 USDC/CZ contract that lives/will live on starknet, this is for USDC/CZ deposits and withdrawals
# use the transfer from function to send the token from sender to recipient
@contract_interface
namespace Erc20:
    func ERC20_transferFrom(sender: felt, recipient: felt, amount: Uint256) -> ():
    end
    func ERC20_transfer(recipient: felt, amount: Uint256) -> ():
    end
    func ERC20_balanceOf(account: felt) -> (balance: Uint256):
    end
    func ERC20_decimals() -> (decimals: felt):
    end    
    func ERC20_allowance(owner: felt, spender: felt) -> (remaining: Uint256):
    end   
    func ERC20_mint(recipient: felt, amount: Uint256) -> ():
    end   
    func ERC20_burn(account: felt, amount: Uint256) -> ():
    end   
end

# @dev interface for the settings contract
@contract_interface
namespace Settings:
    func get_max_capital() -> (max_capital : felt):
    end
    func get_uncollateralised_split() -> (uncol_split : felt, max_uncol_split : felt):
    end
    func get_origination_fee() -> (fee : felt, pp_split : felt, if_split : felt):
    end
    func get_accrued_interest_split() -> (lp_split : felt, if_split : felt, gt_split : felt):
    end
    func get_min_max_loan() -> (min_loan : felt, max_loan : felt):
    end   
    func get_min_max_deposit() -> (min_deposit : felt, max_deposit : felt):
    end
    func get_utilization() -> (stop : felt):
    end   
    func get_insurance_shortfall_ratio() -> (insurance_shortfall_ratio : felt):
    end
    func get_max_loan_term() -> (max_term : felt):
    end
    func get_weth_ltv() -> (ltv : felt):
    end
    func get_weth_liquidation_ratio() -> (ratio : felt):
    end
    func get_weth_liquidation_fee() -> (fee : felt):
    end
    func get_grace_period() -> (period: felt):
    end
    func get_lp_yield_boost() -> (spread: felt):
    end
end

##################################################################
# interface for the oracle contract
@contract_interface
namespace Oracle:
    func get_oracle_price() -> (price : felt):
    end    
    func get_oracle_decimals() -> (decimals : felt):
    end   
end

##################################################################
# interface for the capitalborrow contract
@contract_interface
namespace CapitalBorrower:
    func view_loan_detail(user : felt) -> (
        notional : felt, collateral : felt, start_ts : felt, reval_ts : felt, end_ts : felt, rate : felt, hist_accrual : felt, hist_repay : felt, liquidate_me : felt, accrued_interest : felt):
    end    
end

##################################################################
# interface for the priceprovider contract
@contract_interface
namespace PriceProvider:
    func get_rate(expiry_ts : felt) -> (rate : felt):
    end    
    func get_curve_points() -> (data_len : felt, data : felt*):
    end    
end