####################################################################################
# @title Math10xx8 contract
# @dev this is the math library that we use for CurveZero
# there is still quite large risk of overflow errors, we to check and refine this NB NB NB
# ideally we can switch this out with a native safe math library for cairo once developed
# Functions include
# - assert within Math10xx8 range 
# - convert Math10xx8 to felt
# - convert from felt to Math10xx8
# - convert felt to uint256
# - convert uint256 to felt
# - convert Math10xx8 to erc20 contract number
# - convert erc20 contract number to Math10xx8
# - Math10xx8 zero
# - Math10xx8 one
# - Math10xx8 year in seconds
# - Math10xx8 5 minutes in seconds
# - Math10xx8 add
# - Math10xx8 sub
# - Math10xx8 mul
# - Math10xx8 div
# - Math10xx8 power
# - Math10xx8 power frac using x^y = exp(y*ln(x))
# - Math10xx8 sqrt
# - Math10xx8 exp
# - Math10xx8 ln
# - Math10xx8 block timestamp
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.pow import pow
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.math import (assert_le,assert_lt,sqrt,sign,abs_value,signed_div_rem,unsigned_div_rem,assert_not_zero)

const Math10xx8_INT_PART = 10 ** 30
const Math10xx8_FRACT_PART = 10 ** 8
const Math10xx8_BOUND = 10 ** 38
const Math10xx8_ZERO = 0 * Math10xx8_FRACT_PART
const Math10xx8_ONE = 1 * Math10xx8_FRACT_PART
const Math10xx8_TEN = 10 * Math10xx8_FRACT_PART
const Math10xx8_YEAR = 31557600 * Math10xx8_FRACT_PART
const Math10xx8_5MIN = 300 * Math10xx8_FRACT_PART

func Math10xx8_assert10xx8 {range_check_ptr} (x: felt):
    with_attr error_message("Out of range."):
        assert_le(x, Math10xx8_BOUND)
        assert_le(-Math10xx8_BOUND, x)
    end
    return ()
end

# @dev Converts a fixed point value to a felt, truncating the fractional component
func Math10xx8_toFelt {range_check_ptr} (x: felt) -> (res: felt):
    Math10xx8_assert10xx8(x)
    let (res, _) = signed_div_rem(x, Math10xx8_FRACT_PART, Math10xx8_BOUND)
    return (res)
end

# @dev Converts a felt to a fixed point value ensuring it will not overflow
func Math10xx8_fromFelt {range_check_ptr} (x: felt) -> (res: felt):
    with_attr error_message("Out of range."):
        assert_le(x, Math10xx8_INT_PART)
        assert_le(-Math10xx8_INT_PART, x)
    end
    return (x * Math10xx8_FRACT_PART)
end

# @dev Converts a felt to a uint256 value
func Math10xx8_toUint256 (x: felt) -> (res: Uint256):
    let res = Uint256(low = x, high = 0)
    return (res)
end

# @dev Converts a uint256 value into a felt
func Math10xx8_fromUint256 {range_check_ptr} (x: Uint256) -> (res: felt):
    assert x.high = 0
    return (x.low)
end

# @dev Converts 10xx8 number to token number for transactions
# x is 10xx8 fixed point number and y is a positive integer for decimals
func Math10xx8_convert_from {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (power) = Math10xx8_pow(Math10xx8_TEN, y)
    let (multiplier, _) = unsigned_div_rem(power, Math10xx8_ONE)
    let (res) = Math10xx8_mul(x, multiplier)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Converts token number to a 10xx8 fixed point number
# x is token number and y is a positive integer for decimals
func Math10xx8_convert_to {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (partial) = Math10xx8_fromFelt(x)
    let (power_partial) = Math10xx8_pow(Math10xx8_TEN, y)
    let (power, _) = unsigned_div_rem(power_partial, Math10xx8_ONE)
    let (res, _) = unsigned_div_rem(partial, power)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev returns the constant zero
func Math10xx8_zero {range_check_ptr} () -> (res: felt):
    return (Math10xx8_ZERO)
end

# @dev returns the constant one
func Math10xx8_one {range_check_ptr} () -> (res: felt):
    return (Math10xx8_ONE)
end

# @dev returns the constant year secounds
func Math10xx8_year {range_check_ptr} () -> (res: felt):
    return (Math10xx8_YEAR)
end

# @dev returns the constant 5mins secounds
func Math10xx8_5min {range_check_ptr} () -> (res: felt):
    return (Math10xx8_5MIN)
end

# @dev Convenience addition method to assert no overflow before returning
func Math10xx8_add {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let res = x + y
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Convenience subtraction method to assert no overflow before returning
func Math10xx8_sub {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    # starknet cli returns 1-2 = -1, voyager explorer returns 1-2 = overflow
    # not sure what to trust, have raised question with starkware
    # in meanwhile hard asset y <= x
    with_attr error_message("y should be less or equal to x."):
        assert_le(y, x)
    end
    let res = x - y
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Multiples two fixed point values and checks for overflow before returning
func Math10xx8_mul {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    tempvar product = x * y
    let (res, _) = signed_div_rem(product, Math10xx8_FRACT_PART, Math10xx8_BOUND)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Divides two fixed point values and checks for overflow before returning
# Both values may be signed (i.e. also allows for division by negative b)
func Math10xx8_div {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (div) = abs_value(y)
    let (div_sign) = sign(y)
    tempvar product = x * Math10xx8_FRACT_PART
    let (res_u, _) = signed_div_rem(product, div, Math10xx8_BOUND)
    Math10xx8_assert10xx8(res_u)
    return (res = res_u * div_sign)
end

# @dev Calclates the value of x^y and checks for overflow before returning
# x is a 10xx8 fixed point value
# y is a standard felt (int)
func Math10xx8_pow {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (exp_sign) = sign(y)
    let (exp_val) = abs_value(y)
    if exp_sign == 0:
        return (Math10xx8_ONE)
    end
    if exp_sign == -1:
        let (num) = Math10xx8_pow(x, exp_val)
        return Math10xx8_div(Math10xx8_ONE, num)
    end
    let (half_exp, rem) = unsigned_div_rem(exp_val, 2)
    let (half_pow) = Math10xx8_pow(x, half_exp)
    let (res_p) = Math10xx8_mul(half_pow, half_pow)
    if rem == 0:
        Math10xx8_assert10xx8(res_p)
        return (res_p)
    else:
        let (res) = Math10xx8_mul(res_p, x)
        Math10xx8_assert10xx8(res)
        return (res)
    end
end

# @dev Calclates the value of x^y and checks for overflow before returning
# uses x^y = exp(y*ln(x))
# x is a 10xx8 fixed point value x>0
# y is a 10xx8 fixed point value y>0
func Math10xx8_pow_frac {range_check_ptr} (x: felt, y: felt) -> (res: felt):
    alloc_locals
    let (ln_x) = Math10xx8_ln(x)
    let (y_ln_x) = Math10xx8_mul(y,ln_x)
    let (res) = Math10xx8_exp(y_ln_x)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Calculates the square root of a fixed point value
# x must be positive
func Math10xx8_sqrt {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    let (root) = sqrt(x)
    let (scale_root) = sqrt(Math10xx8_FRACT_PART)
    let (res, _) = signed_div_rem(root * Math10xx8_FRACT_PART, scale_root, Math10xx8_BOUND)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Calculates the most significant bit where x is a fixed point value
# TODO: use binary search to improve performance
func Math10xx8__msb {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    let (cmp) = is_le(x, Math10xx8_FRACT_PART)
    if cmp == 1:
        return (0)
    end
    let (div, _) = unsigned_div_rem(x, 2)
    let (rest) = Math10xx8__msb(div)
    local res = 1 + rest
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Calculates the binary exponent of x: 2^x
func Math10xx8_exp2 {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    let (exp_sign) = sign(x)
    if exp_sign == 0:
        return (Math10xx8_ONE)
    end
    let (exp_value) = abs_value(x)
    let (int_part, frac_part) = unsigned_div_rem(exp_value, Math10xx8_FRACT_PART)
    let (int_res) = Math10xx8_pow(2 * Math10xx8_ONE, int_part)
    # @dev 1.069e-7 maximum error
    const a1 = 99999989
    const a2 = 69315475
    const a3 = 24013971
    const a4 = 5586624
    const a5 = 894283
    const a6 = 189646
    let (r6) = Math10xx8_mul(a6, frac_part)
    let (r5) = Math10xx8_mul(r6 + a5, frac_part)
    let (r4) = Math10xx8_mul(r5 + a4, frac_part)
    let (r3) = Math10xx8_mul(r4 + a3, frac_part)
    let (r2) = Math10xx8_mul(r3 + a2, frac_part)
    tempvar frac_res = r2 + a1
    let (res_u) = Math10xx8_mul(int_res, frac_res)
    if exp_sign == -1:
        let (res_i) = Math10xx8_div(Math10xx8_ONE, res_u)
        Math10xx8_assert10xx8(res_i)
        return (res_i)
    else:
        Math10xx8_assert10xx8(res_u)
        return (res_u)
    end
end

# @dev Calculates the natural exponent of x: e^x
func Math10xx8_exp {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    const mod = 144269504
    let (bin_exp) = Math10xx8_mul(x, mod)
    let (res) = Math10xx8_exp2(bin_exp)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Calculates the binary logarithm of x: log2(x)
# x must be greather than zero
func Math10xx8_log2 {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    if x == Math10xx8_ONE:
        return (0)
    end
    let (is_frac) = is_le(x, Math10xx8_FRACT_PART - 1)
    # @dev Compute negative inverse binary log if 0 < x < 1
    if is_frac == 1:
        let (div) = Math10xx8_div(Math10xx8_ONE, x)
        let (res_i) = Math10xx8_log2(div)
        return (-res_i)
    end
    let (x_over_two, _) = unsigned_div_rem(x, 2)
    let (b) = Math10xx8__msb(x_over_two)
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
    let (r9) = Math10xx8_mul(a9, norm)
    let (r8) = Math10xx8_mul(r9 + a8, norm)
    let (r7) = Math10xx8_mul(r8 + a7, norm)
    let (r6) = Math10xx8_mul(r7 + a6, norm)
    let (r5) = Math10xx8_mul(r6 + a5, norm)
    let (r4) = Math10xx8_mul(r5 + a4, norm)
    let (r3) = Math10xx8_mul(r4 + a3, norm)
    let (r2) = Math10xx8_mul(r3 + a2, norm)
    local norm_res = r2 + a1
    let (int_part) = Math10xx8_fromFelt(b)
    local res = int_part + norm_res
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Calculates the natural logarithm of x: ln(x)
# x must be greater than zero
func Math10xx8_ln {range_check_ptr} (x: felt) -> (res: felt):
    alloc_locals
    const ln_2 = 69314718
    let (log2_x) = Math10xx8_log2(x)
    let (res) = Math10xx8_mul(log2_x, ln_2)
    Math10xx8_assert10xx8(res)
    return (res)
end

# @dev Returns block ts in 10xx8 format
func Math10xx8_ts {syscall_ptr : felt*,range_check_ptr} () -> (res: felt):
    alloc_locals
    let (block_ts) = get_block_timestamp()
    tempvar res = block_ts * Math10xx8_ONE
    Math10xx8_assert10xx8(res)
    return (res)
end
