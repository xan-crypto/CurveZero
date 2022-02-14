# put all interfaces here

%lang starknet
from starkware.cairo.common.uint256 import (Uint256)

##################################################################
# interface to trusted addy contract
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
    func get_czcore_addy() -> (addy : felt):
    end
    func get_controller_addy() -> (addy : felt):
    end
    func get_settings_addy() -> (addy : felt):
    end
    func get_usdc_addy() -> (addy : felt):
    end
    func get_czt_addy() -> (addy : felt):
    end
end

##################################################################
# interfaces to CZCore contract
@contract_interface
namespace CZCore:
    func get_lp_balance(user : felt) -> (lp_user : felt, lockup: felt):
    end
    func set_lp_balance(user : felt, lp_user : felt, lockup : felt):
    end
    func get_cz_state() -> (res : (felt, felt, felt, felt)):
    end
    func set_lp_total(amount : felt):
    end
    func set_capital_total(amount : felt):
    end
    func erc20_transferFrom(erc_addy : felt, sender: felt, recipient: felt, amount: felt):
    end
    func get_pp_status(user : felt) -> (lp_locked : felt, cz_locked : felt, status : felt):
    end
    func set_pp_status(user : felt, lp_user : felt, lp_amount : felt, cz_amount : felt, lockup : felt, promote : felt):
    end  
    func get_cb_loan(user : felt) -> (has_loan : felt, amount : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt):
    end  
    func set_cb_loan(user : felt, has_loan : felt, amount : felt, collateral : felt, start_ts : felt, end_ts : felt, rate : felt, refinance : felt):
    end  
end

##################################################################
# interface to controller contract
@contract_interface
namespace Controller:
    func is_paused() -> (addy : felt):
    end
end

##################################################################
# need interface to the ERC-20 USDC/CZ contract that lives/will live on starknet, this is for USDC/CZ deposits and withdrawals
# use the transfer from function to send the token from sender to recipient
@contract_interface
namespace ERC20:
    func ERC20_transferFrom(sender: felt, recipient: felt, amount: Uint256) -> ():
    end
end

##################################################################
# interface for the settings contract
@contract_interface
namespace Settings:
    func get_pp_token_requirement() -> (lp_require : felt, cz_require : felt):
    end    
    func set_pp_token_requirement(lp_require : felt, cz_require : felt):
    end
    func get_lockup_period() -> (lockup : felt):
    end
    func set_lockup_period(lockup : felt):
    end
end
