####################################################################################
# @title Math10xx18 contract
# @dev this is the math library that we use for CurveZero
# there is still quite large risk of overflow errors, we to check and refine this NB NB NB
# ideally we can switch this out with a native safe math library for cairo once developed
# Functions include
# - assert within Math10xx18 range 
# - convert Math10xx18 to felt
# - convert from felt to Math10xx18
# - convert felt to uint256
# - convert uint256 to felt
# - convert Math10xx18 to erc20 contract number
# - convert erc20 contract number to Math10xx18
# - Math10xx18 zero
# - Math10xx18 one
# - Math10xx18 year in seconds
# - Math10xx18 add
# - Math10xx18 sub
# - Math10xx18 mul
# - Math10xx18 div
# - Math10xx18 power
# - Math10xx18 power frac using x^y = exp(y*ln(x))
# - Math10xx18 sqrt
# - Math10xx18 exp
# - Math10xx18 ln
# - Math10xx18 block timestamp
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.pow import pow
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.math import (assert_le,assert_lt,sqrt,sign,abs_value,signed_div_rem,unsigned_div_rem,assert_not_zero,assert_in_range,assert_nn_le)

const Math10xx18_INT_PART = 10 ** 52
const Math10xx18_FRACT_PART = 10 ** 18
const Math10xx18_BOUND = 10 ** 70
const Math10xx18_ZERO = 0 * Math10xx18_FRACT_PART
const Math10xx18_ONE = 1 * Math10xx18_FRACT_PART
const Math10xx18_TEN = 10 * Math10xx18_FRACT_PART
const Math10xx18_YEAR = 31557600 * Math10xx18_FRACT_PART

func Math10xx18_assert10xx18 {range_check_ptr} (x: felt):
    with_attr error_message("Number not in range."):
        assert_in_range(x, 0, Math10xx18_BOUND)
    end
    return ()
end

# @dev Converts a fixed point value to a felt, truncating the fractional component
@view
func Math10xx18_toFelt {range_check_ptr} (x: felt) -> (res: felt):
    Math10xx18_assert10xx18(x)		
    let (res, _) = unsigned_div_rem(x, Math10xx18_FRACT_PART)
    return (res)
end

# @dev Converts a felt to a fixed point value ensuring it will not overflow
@view
func Math10xx18_fromFelt {range_check_ptr} (x: felt) -> (res: felt):
    with_attr error_message("Number not in range."):
        assert_in_range(x, 0, Math10xx18_INT_PART)
    end
    return (x * Math10xx18_FRACT_PART)
end

# @dev Converts a felt to a uint256 value
@view
func Math10xx18_toUint256 (x: felt) -> (res: Uint256):
    Math10xx18_assert10xx18(x)	
    let res = Uint256(low = x, high = 0)
    return (res)
end

# @dev Converts a uint256 value into a felt
@view
func Math10xx18_fromUint256 {range_check_ptr} (x: Uint256) -> (res: felt):
    assert x.high = 0
    Math10xx18_assert10xx18(x.low)	
    return (x.low)
end

# @dev Converts 10xx18 number to token number for transactions
# x is 10xx18 fixed point number and y is a positive integer for decimals
@view
func Math10xx18_convert_from {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (power) = Math10xx18_pow(Math10xx18_TEN, y)
    let (multiplier, _) = unsigned_div_rem(power, Math10xx18_ONE)
    let (res) = Math10xx18_mul(x, multiplier)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Converts token number to a 10xx18 fixed point number
# x is token number and y is a positive integer for decimals
@view
func Math10xx18_convert_to {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (partial) = Math10xx18_fromFelt(x)
    let (power_partial) = Math10xx18_pow(Math10xx18_TEN, y)
    let (power, _) = unsigned_div_rem(power_partial, Math10xx18_ONE)
    let (res, _) = unsigned_div_rem(partial, power)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev returns the constant zero
@view
func Math10xx18_zero {range_check_ptr} () -> (res: felt):
    return (Math10xx18_ZERO)
end

# @dev returns the constant one
@view
func Math10xx18_one {range_check_ptr} () -> (res: felt):
    return (Math10xx18_ONE)
end

# @dev returns the constant year secounds
@view
func Math10xx18_year {range_check_ptr} () -> (res: felt):
    return (Math10xx18_YEAR)
end

# @dev Convenience addition method to assert no overflow before returning
@view
func Math10xx18_add {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let res = x + y
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Convenience subtraction method to assert no overflow before returning
@view
func Math10xx18_sub {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    with_attr error_message("Number not in range."):
        assert_nn_le(y, x)
    end
    let res = x - y
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Multiples two fixed point values and checks for overflow before returning
@view
func Math10xx18_mul {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    tempvar product = x * y
    let (res, _) = unsigned_div_rem(product, Math10xx18_FRACT_PART)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Divides two fixed point values and checks for overflow before returning
# Both values may be signed (i.e. also allows for division by negative b)
@view
func Math10xx18_div {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    Math10xx18_assert10xx18(x)
    Math10xx18_assert10xx18(y)
    tempvar product = x * Math10xx18_FRACT_PART
    let (res, _) = unsigned_div_rem(product, y)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Calclates the value of x^y and checks for overflow before returning
# x is a 10xx18 fixed point value
# y is a standard felt (int)
@view
func Math10xx18_pow {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (exp_sign) = sign(y)
    let (exp_val) = abs_value(y)
    if exp_sign == 0:
        return (Math10xx18_ONE)
    end
    if exp_sign == -1:
        let (num) = Math10xx18_pow(x, exp_val)
        return Math10xx18_div(Math10xx18_ONE, num)
    end
    let (half_exp, rem) = unsigned_div_rem(exp_val, 2)
    let (half_pow) = Math10xx18_pow(x, half_exp)
    let (res_p) = Math10xx18_mul(half_pow, half_pow)
    if rem == 0:
        Math10xx18_assert10xx18(res_p)
        return (res_p)
    else:
        let (res) = Math10xx18_mul(res_p, x)
        Math10xx18_assert10xx18(res)
        return (res)
    end
end

# @dev Calclates the value of x^y and checks for overflow before returning
# uses x^y = exp(y*ln(x))
# x is a 10xx18 fixed point value x>0
# y is a 10xx18 fixed point value y>0
@view
func Math10xx18_pow_frac {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (ln_x) = Math10xx18_ln(x)
    let (y_ln_x) = Math10xx18_mul(y,ln_x)
    let (res) = Math10xx18_exp(y_ln_x)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Calculates the square root of a fixed point value
# x must be positive
@view
func Math10xx18_sqrt {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    Math10xx18_assert10xx18(x)
    let (root) = sqrt(x)
    let (scale_root) = sqrt(Math10xx18_FRACT_PART)
    let (res, _) = unsigned_div_rem(root * Math10xx18_FRACT_PART, scale_root)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Calculates the most significant bit where x is a fixed point value
# TODO: use binary search to improve performance
@view
func Math10xx18__msb {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    let (cmp) = is_le(x, Math10xx18_FRACT_PART)
    if cmp == 1:
        return (0)
    end
    let (div, _) = unsigned_div_rem(x, 2)
    let (rest) = Math10xx18__msb(div)
    local res = 1 + rest
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Calculates the binary exponent of x: 2^x
@view
func Math10xx18_exp2 {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    let (exp_sign) = sign(x)
    if exp_sign == 0:
        return (Math10xx18_ONE)
    end
    let (exp_value) = abs_value(x)
    let (int_part, frac_part) = unsigned_div_rem(exp_value, Math10xx18_FRACT_PART)
    let (int_res) = Math10xx18_pow(2 * Math10xx18_ONE, int_part)
    # @dev 1.069e-7 maximum error
    const a1 = 99999989
    const a2 = 69315475
    const a3 = 24013971
    const a4 = 5586624
    const a5 = 894283
    const a6 = 189646
    let (r6) = Math10xx18_mul(a6, frac_part)
    let (r5) = Math10xx18_mul(r6 + a5, frac_part)
    let (r4) = Math10xx18_mul(r5 + a4, frac_part)
    let (r3) = Math10xx18_mul(r4 + a3, frac_part)
    let (r2) = Math10xx18_mul(r3 + a2, frac_part)
    tempvar frac_res = r2 + a1
    let (res_u) = Math10xx18_mul(int_res, frac_res)
    if exp_sign == -1:
        let (res_i) = Math10xx18_div(Math10xx18_ONE, res_u)
        Math10xx18_assert10xx18(res_i)
        return (res_i)
    else:
        Math10xx18_assert10xx18(res_u)
        return (res_u)
    end
end

# @dev Calculates the natural exponent of x: e^x
@view
func Math10xx18_exp {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    const mod = 144269504
    let (bin_exp) = Math10xx18_mul(x, mod)
    let (res) = Math10xx18_exp2(bin_exp)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Calculates the binary logarithm of x: log2(x)
# x must be greather than zero
@view
func Math10xx18_log2 {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    if x == Math10xx18_ONE:
        return (0)
    end
    let (is_frac) = is_le(x, Math10xx18_FRACT_PART - 1)
    # @dev Compute negative inverse binary log if 0 < x < 1
    if is_frac == 1:
        let (div) = Math10xx18_div(Math10xx18_ONE, x)
        let (res_i) = Math10xx18_log2(div)
        return (-res_i)
    end
    let (x_over_two, _) = unsigned_div_rem(x, 2)
    let (b) = Math10xx18__msb(x_over_two)
    let (divisor) = pow(2, b)
    let (norm, _) = unsigned_div_rem(x, divisor)
    # @dev 4.233e-8 maximum error
    const a1 = -342539315
    const a2 = 815480447
    const a3 = -1000713624
    const a4 = 928598507
    const a5 = -601343384
    const a6 = 263877455
    const a7 = -74835766
    const a8 = 12384575
    const a9 = -908891
    let (r9) = Math10xx18_mul(a9, norm)
    let (r8) = Math10xx18_mul(r9 + a8, norm)
    let (r7) = Math10xx18_mul(r8 + a7, norm)
    let (r6) = Math10xx18_mul(r7 + a6, norm)
    let (r5) = Math10xx18_mul(r6 + a5, norm)
    let (r4) = Math10xx18_mul(r5 + a4, norm)
    let (r3) = Math10xx18_mul(r4 + a3, norm)
    let (r2) = Math10xx18_mul(r3 + a2, norm)
    local norm_res = r2 + a1
    let (int_part) = Math10xx18_fromFelt(b)
    local res = int_part + norm_res
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Calculates the natural logarithm of x: ln(x)
# x must be greater than zero
@view
func Math10xx18_ln {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    const ln_2 = 69314718
    let (log2_x) = Math10xx18_log2(x)
    let (res) = Math10xx18_mul(log2_x, ln_2)
    Math10xx18_assert10xx18(res)
    return (res)
end

# @dev Returns block ts in 10xx18 format
@view
func Math10xx18_ts {syscall_ptr : felt*,range_check_ptr} () -> (res: felt):
    alloc_locals
    let (block_ts) = get_block_timestamp()
    tempvar res = block_ts * Math10xx18_ONE
    Math10xx18_assert10xx18(res)
    return (res)
end
