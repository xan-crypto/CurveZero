# this contains all the interfaces that CZCore needs

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
    func get_controller_addy() -> (addy : felt):
    end
end

# interface to controller contract
@contract_interface
namespace Controller:
    func is_paused() -> (addy : felt):
    end
end
