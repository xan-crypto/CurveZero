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
    func erc20_transferFrom(sender: felt, recipient: felt, amount: felt):
    end
end

##################################################################
# interface to controller contract
@contract_interface
namespace Controller:
    func is_paused() -> (addy : felt):
    end
end
