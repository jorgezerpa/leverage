#[starknet::contract]
mod EkuboAMMMarginTradingAdapter {

    use leverage::Interfaces::Adapters::EkuboAMMMarginTradingAdapter::IEkuboAMMMarginTradingAdapter;
    use leverage::Interfaces::Shared::{Direction};

    #[storage]
    struct Storage {

    }

    impl EkuboAMMMarginTradingAdapter of IEkuboAMMMarginTradingAdapter<ContractState> {
        fn trade(ref self: ContractState, amount: u256, direction: Direction, data: Array<felt252>) -> (u256, u256, Array<felt252>){
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
            let tradeData:Array<felt252> = ArrayTrait::new(); // any useful data that the 3rd party protocol returns 
            (1,1, tradeData)
        } 

        fn untrade(ref self: ContractState, position_index: u128) {
            
        }

        // for each adapter, there will be a table in docs that relate a number to a specific type, so trade data can be decoded by looping on each felt and using if sentences to decode each value
        fn get_trade_data_types(self: @ContractState) -> Array<u8> {
            let types = ArrayTrait::<u8>::new();
            return types;
        }

    }

}