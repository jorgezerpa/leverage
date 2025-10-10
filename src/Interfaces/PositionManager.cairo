use starknet::{ContractAddress};
use leverage::Interfaces::Shared::{
    Direction,
    MarginState,
    Position
};

#[starknet::interface]
pub trait IPositionManager<TContractState> {
    // for traders
    fn deposit_margin(ref self: TContractState, amount: u256);
    fn open_position(ref self: TContractState, token: ContractAddress, margin_amount_to_use: u256, leverage: u8, direction: Direction ); 
    fn close_position(ref self: TContractState, positionIndex: u64, token: ContractAddress); // in Positions vector  

    // For liquidators 
    fn liquidate_position(ref self: TContractState, positionIndex: u64, token: ContractAddress); // in Positions vector  

    // // admins
    // register new allowed trding pair 

    // // getters 
    fn get_user_margin_state(self: @TContractState, address: ContractAddress) -> MarginState; // returns the totalDeposited margin 
    fn get_position_health(self: @TContractState, token: ContractAddress, positionIndex:u64) -> u256;
    //
    fn get_positions(self: @TContractState, from:u64, to: u64) -> Array<Position>;
    fn get_positions_open(self: @TContractState, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed(self: @TContractState, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position>;
    fn get_positions_open_by_user(self: @TContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed_by_user(self: @TContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position>;
    fn get_positions_open_by_user_by_trading_pair(self: @TContractState, user: ContractAddress, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed_by_user_by_trading_pair(self: @TContractState, user: ContractAddress, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position>;
    // 
    fn get_trading_pair_hash(self: @TContractState, token:ContractAddress) -> felt252;

    // fn estimate_assets_obtained(self: @TContractState, token: ContractAddress, margin_amount: u256, leverage: u8); // returns the amount of tokens that can be buyed with X amount of margin
}

#[derive(Drop, Serde, Copy)]
pub enum View {
    positions, 
    positionsByUser,
    positionsByUserByTradingPair
}
