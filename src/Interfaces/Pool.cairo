use starknet::{ContractAddress};

#[starknet::interface]
pub trait IPool<TContractState> {
    fn allow_token_usage_to_open_position(ref self: TContractState, token: ContractAddress, amount: u256); // @dev should only be callable by PositionManager contract to open positions and/or use funds 
}