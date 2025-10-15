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
    fn open_position(ref self: TContractState, margin_amount_to_use: u256, leverage: u8, direction: Direction, data: Array<felt252> ); 
    fn close_position(ref self: TContractState, positionIndex: u64); // in Positions vector  
    fn liquidate_position(ref self: TContractState, positionIndex: u64); // in Positions vector  

    // // getters 
    fn get_user_margin_state(self: @TContractState, address: ContractAddress) -> MarginState; // returns the totalDeposited margin 
    fn get_position_health(self: @TContractState, positionIndex:u64) -> u256;
    //
    fn get_positions(self: @TContractState, from:u64, to: u64) -> Array<Position>;
    fn get_positions_open(self: @TContractState, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed(self: @TContractState, from:u64, to: u64) -> Array<Position>;
    fn get_positions_open_by_user(self: @TContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed_by_user(self: @TContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position>;
}

#[derive(Drop, Serde, Copy)]
pub enum View {
    positions, 
    positionsByUser,
}
