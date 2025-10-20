use leverage::Interfaces::Shared::{Direction};
use leverage::Interfaces::Adapters::AdapterBase::IAdapterBase;

#[starknet::contract]
mod MockTradingAdapter {
    use starknet::{ContractAddress, get_caller_address};
use starknet::storage::{Vec, MutableVecTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::IAdapterBase;
    use leverage::Interfaces::Shared::{Direction};

    #[storage]
    struct Storage {
        positionManager: ContractAddress,
        tradeDataTypes: Vec<felt252>, // allowed types -> 'integer', 'string', 'address' -> returned data types 
    }

    #[constructor]
    fn constructor(ref self: ContractState, positionManager: ContractAddress) {
        self.positionManager.write(positionManager);
    }

    #[abi(embed_v0)]
    impl EkuboAMMMarginTradingAdapter of IAdapterBase<ContractState> {
        fn trade(ref self: ContractState, amount: u256, direction: Direction, data: Array<felt252>) -> (u256, u256, Array<felt252>){
            assert!(get_caller_address() == self.positionManager.read(), "ONLY POSITION MANAGER");
                // this is custom logic for ekubo adapter 
                // match direction {
                //     Direction::bullish => {
                //         // If direction is bullish, perform a swap "underlying->counter"
                //         traded_asset_price = 1000000_u256; // simulate result for unit counter price calculation -> this is used to store the Position on the correspondant price range 
                //         total_traded_asset = 10000000_u256; // simulate 10 counter tokens was buyed
                //     },
                //     Direction::bearish => {
                //         // IF direction is bearish, then do not perform the swap, just fetch the price and set apart the correspondant underlying to rebuy the asset when close the position
                //         // (this is equivalent to swap the counter for the underlying to go short)
                //         // @dev when close the position, we will buy the counter token and give it back to the trader, so -> the part the protocol keeps should be swaped to underlying 
                //         // @dev should we still make a swap? because the user should deposit or directly transfer the counter they want to sell. OR we just take the equivalent from the deposited margin in underlying? so if they wants to get rid of his counter, they have to swap it and then deposit it here? if choose this last option, we should abstract that swap logic directly -> like give the options "use margin" or "deposit counter" -> this could be made on the front? or it's better to embed on this function as receive a paramenter to choose? or create another specific function follwing DRY principle?
                //         traded_asset_price = 1000000_u256;  
                //         total_traded_asset = 10000000_u256; 
                //     }
                // }
            let mut tradeData:Array<felt252> = ArrayTrait::new(); // any useful data that the 3rd party protocol returns 
            tradeData.append(1); // first element should always be the length of the data
            // RETURN MOCK VALUES TO EVALUATE ON TESTS -> this values should be correctly on Position  
            (0,0, tradeData) // traded_asset_price, total_traded_asset, trade_data
        } 

        fn untrade(ref self: ContractState, position_index: u64) {
            assert!(get_caller_address() == self.positionManager.read(), "ONLY POSITION MANAGER");
            
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
    }

}

