use leverage::Interfaces::Shared::Direction;

#[starknet::interface]
pub trait IAdapterBase<TContractState> {
    fn trade(ref self: TContractState, amount: u256, direction: Direction, data: Array<felt252>) -> (u256, u256, Array<felt252>); // return unit price and total acquired traded asset
    fn untrade(ref self: TContractState, position_index: u64); // performs close position logic, like -> swaps, execute options or futures, etc -> transfers underlying to position manager
    fn get_trade_data_types(self: @TContractState) -> Array<felt252>;
    fn set_trade_data_types(ref self: TContractState, types: Array<felt252>); // ONLY ADMIN
    fn calculate_health(self: @TContractState, positionIndex:u64) -> u256;
    fn is_liquidable(self: @TContractState, positionIndex:u64) -> bool;
    // 
    fn get_traded_asset_current_unit_price(self: @TContractState) -> u256; 
}