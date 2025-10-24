use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct MarginState {
    pub total: u256,
    pub used: u256
}

#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct Position {
    pub deadline: u64,
    pub isOpen: bool, // false when is closed or liquidated 
    pub virtualIndexOnPositionsOpen: u64, // IT SHOULD ADD ON OF THIS FOR EACH POSITION VIEW, because index will be different or (maybe) make views mappings so I stora position on the same "index" key? will this overite other positions?
    pub virtualIndexOnPositionsOpenByUser:u64,
    pub owner: ContractAddress, // the one who opens the position 
    pub leverage: u8,
    pub total_underlying_used: u256, // total_underlying_used/leverage = total margin used @dev this division should always has module=0 AKA when register multiplies, so this is the inverse 
    pub total_traded_assets: u256, // the counter asset on the trading pair 
    pub direction: Direction,
    pub openPrice: u256 // the price of a unit of the traded assets in terms of the underlying asset -> this is what determine the price thick to be stored 
}


#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
#[allow(starknet::store_no_default_variant)]
pub enum Direction {
    bullish,
    bearish
}