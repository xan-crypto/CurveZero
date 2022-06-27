####################################################################################
# @title PriceProvider contract
# @dev all numbers passed into contract must be Math10xx8 type
# Users can
# - request the simple interest rate for any timestamp (linear interpolation)
# - request the full curve points
# Owner can
# - update the full curve points
# if the timestamp is prior the first ts in the curve => raise error
# if the timestamp is after the last ts in the curve => raise error
# added check that the data is not stale
# added check that the rate return should always be >= to the rate of the first point (implied flat for upward sloping yield curve)
# This contract addy will be stored in the TrustedAddy contract
# This contract will be called from the CB contract or external
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import get_caller_address
from InterfaceAll import TrustedAddy, CZCore, Settings, Erc20
from Functions.Math10xx8 import Math10xx8_ts, Math10xx8_sub, Math10xx8_div, Math10xx8_mul, Math10xx8_add
from Functions.Checks import check_is_owner, check_user_balance
from starkware.cairo.common.alloc import alloc

####################################################################################
# @dev storage for the addy of the owner
# this is needed so that the owner can point this contract to the TrustedAddy contract
# this allows for upgradability of this contract
####################################################################################
@storage_var
func owner_addy() -> (addy : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    owner_addy.write(owner)
    return ()
end

@view
func get_owner_addy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (addy : felt):
    let (addy) = owner_addy.read()
    return (addy)
end


####################################################################################
# @dev storage for the different curve points + storage for the capture timestamp
####################################################################################
@storage_var
func curve_points() -> (data : (felt, felt, felt, felt, felt, felt, felt, felt)):
end

@storage_var
func curve_capture() -> (ts : felt):
end

@view
func get_curve_capture{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (ts : felt):
    let (ts) = curve_capture.read()
    return (ts)
end

####################################################################################
# @dev owner can set curve points
# @param
# - the capture timestamp for comparison to the block timestamp
# - the data array lenght
# - the data array
# currently fixed len of n, if n-2x pounts then x 0,0 points at front of curve, owner update will ensure conforms
####################################################################################
@external
func set_curve_points{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(ts_capture : felt, data_len : felt, data : felt*):
    let (owner) = owner_addy.read()
    check_is_owner(owner)
    with_attr error_message("Data lenght must be 8"):
        assert data_len = 8
    end
    # check_ts_expiry(ts_capture)
    curve_capture.write(ts_capture)
    curve_points.write((data[0],data[1],data[2],data[3],data[4],data[5],data[6],data[7]))
    return ()
end

####################################################################################
# @dev user can get all the curve points [ ts , rate ...]
# drops any 0,0 points from front of curve
# @return
# - curve points
####################################################################################
@view
func get_curve_points{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (data_len : felt, data : felt*):
    alloc_locals
    let (ts_capture) = curve_capture.read()
    # check_ts_expiry(ts_capture)
    let (curve) = curve_points.read()
    let (data : felt*) = alloc()
    let data_len = 8
    assert [data + 0] = curve[0]
    assert [data + 1] = curve[1]
    assert [data + 2] = curve[2]
    assert [data + 3] = curve[3]
    assert [data + 4] = curve[4]
    assert [data + 5] = curve[5]
    assert [data + 6] = curve[6]
    assert [data + 7] = curve[7]
    let (clean_curve_len, clean_curve) = create_clean_curve(data_len, data)
    return (clean_curve_len, clean_curve)
end

####################################################################################
# @dev this function just drops all 0,0 points from front of curve
# param arry in 
# return array out of equal or shorter lenght
####################################################################################
func create_clean_curve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(x_len : felt, x : felt*) -> (y_len : felt, y : felt*):
    alloc_locals
    if x[1] != 0:
        return (x_len, x)
    end
    # @dev recursive call
    let (y_len, y) = create_clean_curve(x_len - 2, x + 2)
    return (y_len, y)
end


####################################################################################
# @dev this function returns the rate at any ts on the curve
# @param ts input
# @return rate
####################################################################################
@view
func get_rate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(ts : felt) -> (rate : felt):
    alloc_locals
    let(data_len, data) = get_curve_points()
    # @dev if before start or after end throw error
    with_attr error_message("Timestamp before first data point in curve"):
        assert_le(data[0], ts)
    end
    with_attr error_message("Timestamp after last data point in curve"):
        assert_le(ts, data[data_len-2])
    end    
    # @dev get interp points and perform linear interp
    let (x1, y1, x2, y2) = get_interpolate_data(ts, data_len, data)
    let (rate) = interpolate(ts, x1, y1, x2, y2)
    return(rate)
end

####################################################################################
# @dev this function returns the interp points x1 <= ts < x2  (x1,y1) and (x2,y2)
####################################################################################
func get_interpolate_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(ts : felt, x_len : felt, x : felt*) -> (x1 : felt, y1 : felt, x2 : felt, y2 : felt):
    alloc_locals
    let (test) = is_le(ts, x[2])
    if test == 1:
        return (x[0], x[1], x[2], x[3])
    end
    let (x1, y1, x2, y2) = get_interpolate_data(ts, x_len - 2, x + 2)
    return (x1, y1, x2, y2)
end

####################################################################################
# @dev this function performs linear interp
# have to handle flat/upward slopping and downward slopping seperately
####################################################################################
func interpolate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(x : felt, x1 : felt, y1 : felt, x2 : felt, y2 : felt) -> (y : felt):
    alloc_locals
    let (test) = is_le(y1, y2)
    if test == 1:
        let (y_diff) = Math10xx8_sub(y2, y1)
        let (x_diff) = Math10xx8_sub(x2, x1)
        let (x_int) = Math10xx8_sub(x, x1)
        let (per) = Math10xx8_div(x_int, x_diff)
        let (add) = Math10xx8_mul(per, y_diff)
        let (res) = Math10xx8_add(y1, add)
        return(res)
    else:
        let (y_diff) = Math10xx8_sub(y1, y2)
        let (x_diff) = Math10xx8_sub(x2, x1)
        let (x_int) = Math10xx8_sub(x, x1)
        let (per) = Math10xx8_div(x_int, x_diff)
        let (sub) = Math10xx8_mul(per, y_diff)
        let (res) = Math10xx8_sub(y1, sub)
        return(res)
    end
end