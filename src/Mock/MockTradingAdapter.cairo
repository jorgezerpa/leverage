use leverage::Interfaces::Shared::{Direction};
use leverage::Interfaces::Adapters::AdapterBase::IAdapterBase;

#[starknet::interface]
pub trait ITestingHelper<TContractState> {
    fn set_position_mock_value(ref self: TContractState, position: u64, value: u256);
}

#[starknet::contract]
mod MockTradingAdapter {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::storage::{Vec, MutableVecTrait};
    use super::IAdapterBase;
    use leverage::Interfaces::Shared::{Direction};
    use leverage::Interfaces::PositionManager::{IPositionManagerDispatcher, IPositionManagerDispatcherTrait};
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_token::erc20::extensions::erc4626::interface::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};

    #[storage]
    struct Storage {
        positionManager: ContractAddress,
        tradeDataTypes: Vec<felt252>, // allowed types -> 'integer', 'string', 'address' -> returned data types 
        // 
        // FOR TEST PURPOSES register the position underlaying used when opens it (calls trade)
        // If you need such position to be liquidable, in loss or with profit, call the helper function "set_position_mock_value" to set a new value
        positionsMockValue: Map<u64, u256> 
    }

    #[constructor]
    fn constructor(ref self: ContractState, positionManager: ContractAddress) {
        self.positionManager.write(positionManager);
    }


    #[abi(embed_v0)]
    impl testingHelper of super::ITestingHelper<ContractState> {
        fn set_position_mock_value(ref self: ContractState, position: u64, value: u256) {
            self.positionsMockValue.entry(position).write(value);
        }
    }

    #[abi(embed_v0)]
    impl EkuboAMMMarginTradingAdapter of IAdapterBase<ContractState> {
        fn trade(ref self: ContractState, amount: u256, direction: Direction, data: Array<felt252>) -> (u256, u256, Array<felt252>){
            assert!(get_caller_address() == self.positionManager.read(), "ONLY POSITION MANAGER");
            let positionManager = IPositionManagerDispatcher { contract_address: self.positionManager.read() };
            self.positionsMockValue.entry(positionManager.get_positions_count()).write(amount);
            
            let mut tradeData:Array<felt252> = ArrayTrait::new(); // any useful data that the 3rd party protocol returns 
            tradeData.append(1); // first element should always be the length of the data
            // RETURN MOCK VALUES TO EVALUATE ON TESTS -> this values should be correctly on Position  
            (0,0, tradeData) // traded_asset_price, total_traded_asset, trade_data
        } 
        
        fn untrade(ref self: ContractState, position_index: u64) {
            assert!(get_caller_address() == self.positionManager.read(), "ONLY POSITION MANAGER");
            let positionManager = IPositionManagerDispatcher { contract_address: self.positionManager.read() };
            let pool = ERC4626ABIDispatcher { contract_address: positionManager.get_pool() };
            let token = ERC20ABIDispatcher { contract_address: pool.asset() };

            token.transfer(positionManager.contract_address, self.positionsMockValue.entry(position_index).read());
            self.positionsMockValue.entry(position_index).read();
        }

        // for each adapter, there will be a table in docs that relate a number to a specific type, so trade data can be decoded by looping on each felt and using if sentences to decode each value
        fn get_trade_data_types(self: @ContractState) -> Array<felt252> {
            let mut array = ArrayTrait::<felt252>::new();

            let numberOfPreviousItems:u64 = self.tradeDataTypes[0].read().try_into().unwrap();
            
            // remove previous types
            for i in 0..numberOfPreviousItems {
                array.append(self.tradeDataTypes[i].read());
            }

            array
        }

        fn set_trade_data_types(ref self: ContractState, types: Array<felt252>) {
            // check only owner

            // check first element on types array (AKA the number of consequent items) is not 0 
            assert!(*types.at(0)!=0, "CAN NOT REGISTER ZERO ITEMS"); 
            
            //
            let tradeDataTypes = self.tradeDataTypes;
            let numberOfPreviousItems:u64 = tradeDataTypes[0].read().try_into().unwrap();
            
            // remove previous types
            if(numberOfPreviousItems!=0) { // if there are items registered
                for i in 0..numberOfPreviousItems { 
                    tradeDataTypes[i].write(0);
                }
            }
            
            // store
            for i in 0..types.len() {
                let t = *types.at(i);
                assert!(t=='u256' || t=='felt252' || t=='ContractAddress', "INVALID TYPE"); // @todo extract this into a custom function, @todo maybe create a admin function "setAllowedTypes" and it getter of course 
                tradeDataTypes[i.into()].write(t);
            }
            
        }

        fn calculate_health(self: @ContractState, positionIndex:u64) -> u256 {
            9999
        }

        fn is_liquidable(self: @ContractState, positionIndex:u64) -> bool {
            let positionManager = IPositionManagerDispatcher { contract_address: self.positionManager.read() };
            let positions = positionManager.get_positions(positionIndex,positionIndex+1);
            let position = *positions.at(0);

            position.total_underlying_used > self.positionsMockValue.entry(positionIndex).read()
        }

        fn get_traded_asset_current_unit_price(self: @ContractState) -> u256 {
            1
        }

        fn get_current_position_value(self: @ContractState, positionIndex: u64) -> u256 {
            self.positionsMockValue.entry(positionIndex).read()
        }
    }

}

