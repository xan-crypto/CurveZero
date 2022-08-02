####################################################################################
# @title Oracle contract
# @dev this contract uses empiric network for the ETH/USD price feed
# this contract can be replaced to point to any data source for the price feed
# @author xan-crypto
####################################################################################

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin

# Oracle Interface Definition
const EMPIRIC_ORACLE_ADDRESS = 0x012fadd18ec1a23a160cc46981400160fbf4a7a5eed156c4669e39807265bcd4
const KEY = 28556963469423460  # str_to_felt("eth/usd")
const AGGREGATION_MODE = 120282243752302  # str_to_felt("median")

@contract_interface
namespace IEmpiricOracle:
    func get_value(key : felt, aggregation_mode : felt) -> (
        value : felt,
        decimals : felt,
        last_updated_timestamp : felt,
        num_sources_aggregated : felt
    ):
    end
end

@storage_var
func oracle_name() -> (name: felt):
end

@storage_var
func oracle_symbol() -> (symbol: felt):
end

@storage_var
func oracle_decimals() -> (decimals: felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(name: felt,symbol: felt):
    oracle_name.write(name)
    oracle_symbol.write(symbol)
    oracle_decimals.write(18)
    return ()
end

@view
func get_oracle_name{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (name: felt):
    let (name) = oracle_name.read()
    return (name)
end

@view
func get_oracle_symbol{syscall_ptr : felt*,pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (symbol: felt):
    let (symbol) = oracle_symbol.read()
    return (symbol)
end

@view
func get_oracle_decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (decimals: felt):
    let (decimals) = oracle_decimals.read()
    return (decimals)
end

@view
func get_oracle_price{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (price: felt):
    let (eth_price, decimals, last_updated_timestamp, num_sources_aggregated) = IEmpiricOracle.get_value(EMPIRIC_ORACLE_ADDRESS, KEY, AGGREGATION_MODE)
    return (eth_price)
end