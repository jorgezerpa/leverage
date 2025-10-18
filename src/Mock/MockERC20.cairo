#[starknet::contract]
mod MockERC20 {
    // components
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig as erc20DefaultConfig};
     
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);    
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }
    
    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }
    
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
    ) {
        self.erc20.initializer(name, symbol);
    }

    ////////////////////
    /// COMPONENTS MIXINS AND IMPLEMENTS
    ////////////////////
    
    // ERC20 
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
}
