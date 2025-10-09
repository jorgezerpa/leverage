use starknet::{ContractAddress};
use leverage::Interfaces::Shared::Direction;

#[starknet::interface]
pub trait IPositionManager<TContractState> {
    // for traders
    fn deposit_margin(ref self: TContractState, amount: u256);
    fn open_position(ref self: TContractState, token: ContractAddress, margin_amount_to_use: u256, leverage: u8, direction: Direction ); 
    fn close_position(ref self: TContractState, positionIndex: u64, token: ContractAddress); // in Positions vector  
    fn liquidate_position(ref self: TContractState, positionIndex: u64, token: ContractAddress); // in Positions vector  
    

    // // for liquidators or keepers
    // fn liquidate_position(ref self: TContractState, positionId: u256);

    // // admins
    // register new allowed trding pair 

    // // getters 
    // fn get_user_margin_state(self: @TContractState, address: ContractAddress) -> u256; // returns the totalDeposited margin 
    // fn get_available_margin(self: @TContractState, address: ContractAddress) -> u256; // returns the unused margin amount
    // fn get_position_health(self: @TContractState, positionId:u256) -> u256;
    // fn estimate_assets_obtained(self: @TContractState, token: ContractAddress, margin_amount: u256, leverage: u8); // returns the amount of tokens that can be buyed with X amount of margin
}

#[derive(Drop, Serde, Copy)]
pub enum View {
    positions, 
    positionsByUser,
    positionsByUserByTradingPair
}
