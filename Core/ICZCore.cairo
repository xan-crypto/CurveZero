# this contains all the interfaces that CZCore needs

%lang starknet

# interface to trusted addys contract
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

# interface to controller contract
@contract_interface
namespace Controller:
    func is_paused() -> (addy : felt):
    end
end

# need interface to the ERC-20 USDC contract that lives on starknet, this is for USDC deposits and withdrawals
# use the transfer from function to send the USDC from sender to recipient
@contract_interface
namespace ERC20_USDC:
    func ERC20_transferFrom(sender: felt, recipient: felt, amount: Uint256) -> ():
    end
end
