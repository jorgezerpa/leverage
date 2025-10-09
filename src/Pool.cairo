// This contract holds the tokens of:
// - LPs funds that will be used ot allow leverage for margin trading (USD based stablecoin)
// - Traders margin (USD based stablecoin)
// - Tokens of opened positions (Any whitelisted ERC20)
// @note this contract acts ONLY AS A VAULT and do not have any logic about positions tracking neither metadata accounting like margin deposited, margin used in positions, etc. -> all this is managed by the position manager 
// @note The position manager has the power to authorize allowance to itself of the tokens of this contract (to open positions or any other app logic)

use starknet::{ContractAddress};


/// Simple contract for managing balance.
#[starknet::contract]
mod Pool {
    ////////////////////
    /// IMPORTS
    ////////////////////
    // base
    use starknet::{ContractAddress};
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};
    use starknet::{
        get_caller_address
    };
    // components
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig as erc20DefaultConfig};
    use openzeppelin_token::erc20::extensions::{
        erc4626::{
            ERC4626Component,
            DefaultConfig as erc4626DefaultConfig,
        }
    };
    use openzeppelin_token::erc20::extensions::erc4626::{ERC4626DefaultNoFees, ERC4626DefaultLimits, ERC4626HooksEmptyImpl}; // @dev why this works by just import and no need to manually impl it?
    // dispatchers
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    //
    use leverage::Interfaces::Pool::IPool;
    
    ////////////////////
    /// DECLARE COMPONENTS
    ////////////////////
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    
    
    ////////////////////
    /// EVENTS
    ////////////////////
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        ERC4626Event: ERC4626Component::Event
    }
    
    ////////////////////
    /// STORAGE
    ////////////////////
    #[storage]
    struct Storage {
        balance: felt252,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        //// custom storage 
        positionManager: ContractAddress
    }
    
    
    ////////////////////
    /// CONSTRUCTOR
    ////////////////////
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        fixed_supply: u256,
        recipient: ContractAddress,
        underlying_asset: ContractAddress,
        // 
        positionManager: ContractAddress
    ) {
        // erc20
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient, fixed_supply);
        // erc4626
        self.erc4626.initializer(underlying_asset);
        // custom storage
        self.positionManager.write(positionManager);
    }

    ////////////////////
    /// COMPONENTS MIXINS AND IMPLEMENTS
    ////////////////////
    
    // ERC20 
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    
    #[abi(embed_v0)]
    impl ERC4626ComponentImpl = ERC4626Component::ERC4626Impl<ContractState>;
    impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;
    
    ////////////////////
    /// CUSTOM LOGIC IMPLEMENTS
    ////////////////////
    impl PoolImpl of IPool<ContractState> {

        /// @dev Important checks should be performed on the PositionManager everytime this function will be called -> Like check the current margin deposited of the caller, check the current used margin, check the health of the caller, etc 
        fn allow_token_usage_to_open_position(ref self: ContractState, token: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            assert!(caller==self.positionManager.read(), "ONLY POSITION MANAGER"); // @todo create constant file to hold error strings
            let token = ERC20ABIDispatcher { contract_address: token };
            // @audit what if token doesn't return anything? -> should be an invariant in whitelisted tokens? like "LISTED TOKENS ALWAYS RETURN A BOOLEAN DURING APPROVES"
            // @TODO use safe libraries like in Solidity (if possible)
            let success = token.approve(caller, amount);
            assert!(success, "FAILED APPROVAL");
        }

    }


}
