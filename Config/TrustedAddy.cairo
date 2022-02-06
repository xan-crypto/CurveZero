# Addys that CZCore accepts

%lang starknet
%builtins pedersen range_check
from starkware.cairo.common.cairo_builtins import HashBuiltin

# addy of the lp contract
@storage_var
func lp_addy() -> (addy : felt):
end

# run on deployment only, must have constructor in name and decorator
@constructor
func constructor{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}(_lp_addy : felt):
    lp_addy.write(_lp_addy)
    return ()
end

# return lp addy
@view
func get_lp_addy{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (addy : felt):
    let (addy) = lp_addy.read()
    return (addy)
end
