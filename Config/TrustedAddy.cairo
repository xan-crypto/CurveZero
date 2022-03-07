####################################################################################
# @title TrustedAddy contract
# @dev all numbers passed into contract must be Math10xx8 type
# This contract stores all the addresses for the contracts in the system
# This enables upgradability because switching out the LP contract for example is as simple as pointing the 
# TrustedAddy contract to the new LP contract and the new LP contract to the existing TrustAddy contract
# This allows the new LP contract to talk to the old CZCore and CZCore to know and expect the new LP contract address
# User can view
# - Owner addy
# - LiquidityProvider addy
# - PriceProvider addy
# - CapitalBorrower addy
# - LoanLiquidator addy
# - GovenanceToken addy
# - InsuranceFund addy
# - CZCore addy
# - Controller addy
# - Settings addy
# - USDC addy
# - CZT addy
# - WETH addy
# - Oracle addy
# Owner can get all of the above except the Owner which is set by the constructor
# @author xan-crypto
####################################################################################

%lang starknet
%builtins pedersen range_check
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from Functions.Checks import check_is_owner

# @dev addy of the owner
@storage_var
func owner_addy() -> (addy : felt):
end

# @dev addy of the lp contract
@storage_var
func lp_addy() -> (addy : felt):
end

# @dev addy of the pp contract
@storage_var
func pp_addy() -> (addy : felt):
end

# @dev addy of the cb contract
@storage_var
func cb_addy() -> (addy : felt):
end

# @dev addy of the ll contract
@storage_var
func ll_addy() -> (addy : felt):
end

# @dev addy of the gt contract
@storage_var
func gt_addy() -> (addy : felt):
end

# @dev addy of the if contract
@storage_var
func if_addy() -> (addy : felt):
end

# @dev addy of the czcore contract
@storage_var
func czcore_addy() -> (addy : felt):
end

# @dev addy of the controller contract
@storage_var
func controller_addy() -> (addy : felt):
end

# @dev addy of the settings contract
@storage_var
func settings_addy() -> (addy : felt):
end

# @dev addy of the ERC-20 USDC contract
@storage_var
func usdc_addy() -> (addy : felt):
end

# @dev addy of the ERC-20 CZT contract
@storage_var
func czt_addy() -> (addy : felt):
end

# @dev addy of the ERC-20 WETH contract
@storage_var
func weth_addy() -> (addy : felt):
end

# @dev addy of the ERC-20 WETH Oracle
@storage_var
func oracle_addy() -> (addy : felt):
end

# @dev set the relevant addys on deployment, is there a better way to do this?
# check with starknet devs
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _owner_addy : felt,
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
    _czt_addy : felt,
    _weth_addy : felt,
    _oracle_addy : felt):
    owner_addy.write(_owner_addy)
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
    weth_addy.write(_weth_addy)
    oracle_addy.write(_oracle_addy)
    return ()
end

# @dev view/set lp addy
@view
func get_lp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = lp_addy.read()
    return (addy)
end
@external
func set_lp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    lp_addy.write(addy)
    return ()
end

# @dev view/set pp addy
@view
func get_pp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = pp_addy.read()
    return (addy)
end
@external
func set_pp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    pp_addy.write(addy)
    return ()
end

# @dev view/set cb addy
@view
func get_cb_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = cb_addy.read()
    return (addy)
end
@external
func set_cb_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    cb_addy.write(addy)
    return ()
end

# @dev view/set ll addy
@view
func get_ll_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = ll_addy.read()
    return (addy)
end
@external
func set_ll_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    ll_addy.write(addy)
    return ()
end

# @dev view/set gt addy
@view
func get_gt_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = gt_addy.read()
    return (addy)
end
@external
func set_gt_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    gt_addy.write(addy)
    return ()
end

# @dev view/set if addy
@view
func get_if_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = if_addy.read()
    return (addy)
end
@external
func set_if_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    if_addy.write(addy)
    return ()
end

# @dev view/set czcore addy
@view
func get_czcore_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = czcore_addy.read()
    return (addy)
end
@external
func set_czcore_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    czcore_addy.write(addy)
    return ()
end

# @dev view/set controller addy
@view
func get_controller_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = controller_addy.read()
    return (addy)
end
@external
func set_controller_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    controller_addy.write(addy)
    return ()
end

# @dev view/set settings addy
@view
func get_settings_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = settings_addy.read()
    return (addy)
end
@external
func set_settings_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    settings_addy.write(addy)
    return ()
end

# @dev view/set the ERC-20 USDC contract addy
@view
func get_usdc_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = usdc_addy.read()
    return (addy)
end
@external
func set_usdc_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    usdc_addy.write(addy)
    return ()
end

# @dev view/set the ERC-20 CZT contract addy
@view
func get_czt_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = czt_addy.read()
    return (addy)
end
@external
func set_czt_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    czt_addy.write(addy)
    return ()
end

# @dev view/set the ERC-20 WETH contract addy
@view
func get_weth_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = weth_addy.read()
    return (addy)
end
@external
func set_weth_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    weth_addy.write(addy)
    return ()
end

# @dev view/set the ERC-20 WETH oracle contract addy
@view
func get_oracle_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = oracle_addy.read()
    return (addy)
end
@external
func set_oracle_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(addy : felt):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    oracle_addy.write(addy)
    return ()
end
