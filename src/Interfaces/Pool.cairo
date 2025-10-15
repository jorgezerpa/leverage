use starknet::{ContractAddress};

#[starknet::interface]
pub trait IPool<TContractState> {
    fn transfer_assets_to_trade(ref self: TContractState, amount: u256, to: ContractAddress); // @dev should only be callable by PositionManager contract to open positions and/or use funds 
}