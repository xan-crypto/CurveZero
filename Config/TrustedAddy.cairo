# the addys of all the contracts in the protocol
# this prevents anyone from calling CZCore functions for example

%lang starknet
%builtins pedersen range_check
from starkware.cairo.common.cairo_builtins import HashBuiltin

##################################################################
# all the trusted addys for the protocol
# addy of the lp contract
@storage_var
func lp_addy() -> (addy : felt):
end

# addy of the pp contract
@storage_var
func pp_addy() -> (addy : felt):
end

# addy of the cb contract
@storage_var
func cb_addy() -> (addy : felt):
end

# addy of the ll contract
@storage_var
func ll_addy() -> (addy : felt):
end

# addy of the gt contract
@storage_var
func gt_addy() -> (addy : felt):
end

# addy of the if contract
@storage_var
func if_addy() -> (addy : felt):
end

# addy of the czcore contract
@storage_var
func czcore_addy() -> (addy : felt):
end

# addy of the controller contract
@storage_var
func controller_addy() -> (addy : felt):
end

# addy of the settings contract
@storage_var
func settings_addy() -> (addy : felt):
end

# addy of the ERC-20 USDC contract
@storage_var
func usdc_addy() -> (addy : felt):
end

# addy of the ERC-20 CZT contract
@storage_var
func czt_addy() -> (addy : felt):
end

# set the relevant addys on deployment, is there a better way to do this?
# check with starknet devs
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _lp_addy : felt,
    _pp_addy : felt,
    _cb_addy : felt,
    _ll_addy : felt,
    _gt_addy : felt,
    _if_addy : felt,
    _czcore_addy : felt,
    _controller_addy : felt,
    _settings_addy : felt,
    _usdc_addy : felt,
    _czt_addy : felt):
    lp_addy.write(_lp_addy)
    pp_addy.write(_pp_addy)
    cb_addy.write(_cb_addy)
    ll_addy.write(_ll_addy)
    gt_addy.write(_gt_addy)
    if_addy.write(_if_addy)
    czcore_addy.write(_czcore_addy)
    controller_addy.write(_controller_addy)
    settings_addy.write(_settings_addy)
    usdc_addy.write(_usdc_addy)
    czt_addy.write(_czt_addy)
    return ()
end

# return lp addy
@view
func get_lp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = lp_addy.read()
    return (addy)
end

# return pp addy
@view
func get_pp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = pp_addy.read()
    return (addy)
end

# return cb addy
@view
func get_cb_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = cb_addy.read()
    return (addy)
end

# return ll addy
@view
func get_ll_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = ll_addy.read()
    return (addy)
end

# return gt addy
@view
func get_gt_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = gt_addy.read()
    return (addy)
end

# return if addy
@view
func get_if_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = if_addy.read()
    return (addy)
end

# return czcore addy
@view
func get_czcore_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = czcore_addy.read()
    return (addy)
end

# return controller addy
@view
func get_controller_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = controller_addy.read()
    return (addy)
end

# return settings addy
@view
func get_settings_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = settings_addy.read()
    return (addy)
end

# get the ERC-20 USDC contract addy
@view
func get_usdc_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = usdc_addy.read()
    return (addy)
end

# get the ERC-20 CZT contract addy
@view
func get_czt_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = czt_addy.read()
    return (addy)
end
