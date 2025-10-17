// use starknet::{ContractAddress};
use leverage::Interfaces::Shared::{Direction};

#[starknet::interface]
pub trait IEkuboAMMMarginTradingAdapter<TContractState> {
    fn trade(ref self: TContractState, amount: u256, direction: Direction, data: Array<felt252>) -> (u256, u256, Array<felt252>); // return unit price and total acquired traded asset
    fn untrade(ref self: TContractState, position_index: u64);
    fn get_trade_data_types(self: @TContractState) -> Array<felt252>;
    fn set_trade_data_types(ref self: TContractState, types: Array<felt252>); // ONLY ADMIN
}


