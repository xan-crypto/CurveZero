# put all interfaces here

%lang starknet

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
end

##################################################################
# interfaces to CZCore contract
@contract_interface
namespace CZCore:
    func get_lp_balance(user : felt) -> (res : felt):
    end
    func set_lp_balance(user : felt, amount : felt):
    end
    func get_lp_total() -> (res : felt):
    end
    func set_lp_total(amount : felt):
    end
    func get_capital_total() -> (res : felt):
    end
    func set_capital_total(amount : felt):
    end
    func get_loan_total() -> (res : felt):
    end
    func set_loan_total(amount : felt):
    end
    func get_insolvency_shortfall() -> (res : felt):
    end
    func set_insolvency_shortfall(amount : felt):
    end    
    func erc20_transferFrom(sender: felt, recipient: felt, amount: felt):
    end
    func get_pp_status(user : felt) -> (res : felt):
    end
    func set_pp_promote(user : felt):
    end
    func set_pp_demote(user : felt):
    end
end

##################################################################
# interface to controller contract
@contract_interface
namespace Controller:
    func is_paused() -> (addy : felt):
    end
    func set_pp_token_requirement(lp_require : felt, cz_require : felt):
    end
end

##################################################################
# need interface to the ERC-20 USDC contract that lives on starknet, this is for USDC deposits and withdrawals
# use the transfer from function to send the USDC from sender to recipient
@contract_interface
namespace ERC20_USDC:
    func ERC20_transferFrom(sender: felt, recipient: felt, amount: Uint256) -> ():
    end
end

##################################################################
# interface for the settings contract
@contract_interface
namespace Settings:
    func set_pp_token_requirement(lp_require : felt, cz_require : felt):
    end
end
