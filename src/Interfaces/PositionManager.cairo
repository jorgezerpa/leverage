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
    fn get_position_from_view(self: @TContractState, indexes:Array<u64>) -> Array<Position>;
    fn get_positions_open(self: @TContractState, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed(self: @TContractState, from:u64, to: u64) -> Array<Position>;
    fn get_positions_open_by_user(self: @TContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position>;
    fn get_positions_closed_by_user(self: @TContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position>;
    //
    fn get_trade_data(self:@TContractState, positionIndex:u64) -> Array<felt252>; // any useful data that the 3rd party protocol returns -> first item (u8) is the length (inclusive) of the array AKA the amount of items it holds @audit this was made because compiler doesnt allow to call len() on vecs in view functions, so it was this OR convert it into "Ref self" but then users would have to pay gas just for view  

    // admin
    fn set_pool(ref self: TContractState, pool_address: ContractAddress);
    fn set_adapter(ref self: TContractState, pool_address: ContractAddress);
    fn get_pool(self: @TContractState) -> ContractAddress;
    fn get_adapter(self: @TContractState) -> ContractAddress;
    fn get_admin(self: @TContractState) -> ContractAddress;
    
}

#[derive(Drop, Serde, Copy)]
pub enum View {
    positions, 
    positionsByUser,
}
