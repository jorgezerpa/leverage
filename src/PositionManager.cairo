use starknet::{ContractAddress};

#[derive(Drop, Serde, Copy, starknet::Store)]
#[allow(starknet::store_no_default_variant)]
enum Direction {
    bullish,
    bearish
}

#[derive(Drop, Serde, Copy)]
enum View {
    positions, 
    positionsByUser,
    positionsByUserByTradingPair
}

#[starknet::interface]
pub trait IPositionManager<TContractState> {
    // for traders
    fn deposit_margin(ref self: TContractState, amount: u256);
    fn open_position(ref self: TContractState, token: ContractAddress, margin_amount_to_use: u256, leverage: u8, direction: Direction ); 
    fn close_position(ref self: TContractState, positionIndex: u64, token: ContractAddress); // in Positions vector  
    
    // // for liquidators or keepers
    // fn liquidate_position(ref self: TContractState, positionId: u256);

    // // admins
    // register new allowed trding pair 

    // // getters 
    // fn get_deposited_margin(self: @TContractState, address: ContractAddress) -> u256; // returns the totalDeposited margin 
    // fn get_available_margin(self: @TContractState, address: ContractAddress) -> u256; // returns the unused margin amount
    // fn get_position_health(self: @TContractState, positionId:u256) -> u256;
    // fn estimate_assets_obtained(self: @TContractState, token: ContractAddress, margin_amount: u256, leverage: u8); // returns the amount of tokens that can be buyed with X amount of margin
}

// Internals 
// calculate_required_margin 

/// Simple contract for managing balance.
#[starknet::contract]
mod PositionManager {
    use super::{IPositionManager,Direction};

    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::pedersen::PedersenTrait;
    use core::num::traits::Bounded;
    
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::storage::{Vec, MutableVecTrait, VecTrait};

    // dispatchers
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_token::erc20::extensions::erc4626::interface::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};
    // 
    

    #[storage]
    struct Storage {
        underlying_asset: ContractAddress, // to do -> read this from pool, not store it here 
        pool: ContractAddress, // lending pool -> Pool contract 
        poolUsedUnderlying: u256, // the amount of underlying that is actually covering a position (AKA lended) -> this should be substracted from pool balance for calculations 
        userMargin: Map<ContractAddress, MarginState>, // deposited and used margin for each user
        // TradingPair->positions
        positions: Map<felt252,Vec<Position>>, // Only add, never remove AKA length ONLY INCREASES 
        positionsOpen: Map<felt252,Vec<u64>>, 
        positionsClosed: Map<felt252,Vec<u64>>,  
        positionsOpenByUser: Map<ContractAddress, Vec<u64>>, // User->positions 
        positionsClosedByUser: Map<ContractAddress, Vec<u64>>, // Historical purposes only -> added when liquidates or closes
        positionsOpenByUserByTradingPair: Map<ContractAddress, Map<felt252,Vec<u64>>>, // User->pair->positions 
        positionsClosedByUserByTradingPair: Map<ContractAddress, Map<felt252,Vec<u64>>>, // User->pair->positions 

    }

    // The storage variables are a bit complex, but this structure is aiming for:
    // - Easy access to data for user (each "ByUser" and "byTrading" variable is like a "view" on a trad DB)
    // - Immutable track of all positions with `position`
    // - O(N) liquidation search complexity -> by looping on `positionsOpen` -> also this removes closed/liquidated positions which reduces overal computational usage
    // - O(K) position remove complexity 
    //      uses a "Swap and Pop" algorithm to remove closed/liquidatable positions from the opened positions registers 
    //      by implementing an unsorted Array (`positionsOpen`) that pairs each index with the correspondant index of the position on "Positions"
    //      When removes only have to swap N for LAST and pop 
    /// WHEN OPEN A POSITION 
    /// - Add it to `positions`
    /// - Add index to it to 'positionsOpen'
    /// - add index to it to `positionsOpenByUser`
    /// - add index to it to `positionsOpenByTradingPairByUser`
    /// HOW TO DETECT LIQUIDABLE POSITIONS
    /// - Loop on each `positionsOpen` item
    /// - If it is liquidadable
    ///     - call `liquidate(index)` and then repeat the same index on the loop, because it was replaced for a new one position  
    /// WHEN LIQUIDATES A POSITION
    /// - Get LAST position and update it's "virtualIndexOnPositionsOpen" property to N -> this modified one is the one who will be replacing the N position
    /// - In `positionsOpen`: Swap N position for LAST position and then pop it -> REMEMBER TO UPDATE the moved position
    /// - push N position to `positionsClosed`
    /// - In `positionsOpenByUser`: Swap N position for LAST position and then pop it (get the owner address from position)
    /// - push N position to `positionsClosedByUser`
    /// - In `positionsOpenByTradingPairByUser`: Swap N position for LAST position and then pop it (get the owner address from position)
    /// - push N position to `positionsClosedByTradingPairByUser`
    /// WHEN CLOSES A POSITION 
    /// - In `positionsOpenByUser`: Swap N position for LAST position and then pop it (get the owner address from position)
    /// - push N position to `positionsClosedByUser`
    /// - In `positionsOpenByTradingPairByUser`: Swap N position for LAST position and then pop it (get the owner address from position)
    /// - push N position to `positionsClosedByTradingPairByUser`
    /// - Remove it from `OpenPositions` by using "virtualIndexOnPositionsOpen" prop 
    /// - Add it to `closedPositions`
    /// HOW USERS GETS POSITIONS 
    /// - Calls getters functions with pagination included (receives from-to indexes)

     ////////////////////
    /// CONSTRUCTOR
    ////////////////////
    #[constructor]
    fn constructor(
        ref self: ContractState,
        underlying_asset: ContractAddress,
        pool: ContractAddress,
    ) {
        self.underlying_asset.write(underlying_asset);
        self.pool.write(pool);
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct MarginState {
        total: u256,
        used: u256
    }

    #[derive(Drop, Serde, Copy, starknet::Store)]
    struct Position {
        isOpen: bool, // false when is closed or liquidated 
        virtualIndexOnPositionsOpen: u64, // IT SHOULD ADD ON OF THIS FOR EACH POSITION VIEW, because index will be different or (maybe) make views mappings so I stora position on the same "index" key? will this overite other positions?
        virtualIndexOnPositionsOpenByUser:u64,
        virtualIndexOnPositionsOpenByUserByTradingPair:u64,
        owner: ContractAddress, // the one who opens the position 
        leverage: u8,
        total_underlying_used: u256, // total_underlying_used/leverage = total margin used @dev this division should always has module=0 AKA when register multiplies, so this is the inverse 
        total_traded_assets: u256, // the counter asset on the trading pair 
        direction: Direction,
        pair: TradingPair,
        openPrice: u256 // the price of a unit of the traded assets in terms of the underlying asset -> this is what determine the price thick to be stored 
    }

    /// Trading pair used to separate positions by pair on storage
    #[derive(Drop, Serde, Copy, Hash, starknet::Store)]
    struct TradingPair {
        underlying_asset: ContractAddress,
        traded_asset: ContractAddress
    }

    #[abi(embed_v0)]
    impl PositionManagerImpl of IPositionManager<ContractState> {
        
        fn deposit_margin(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            // register depositor
            let newMarginState:MarginState = MarginState { total: amount, used: 0 };
            self.userMargin.entry(caller).write(newMarginState);
            
            // get funds
            let token = ERC20ABIDispatcher { contract_address: self.underlying_asset.read() };
            let success = token.transfer_from(caller, self.pool.read(), amount);
            
            assert!(success, "FAILED TRANSFER_FROM");
            
        }
        

        fn open_position(ref self: ContractState, token: ContractAddress, margin_amount_to_use: u256, leverage: u8, direction: Direction ){
            // 1. BASIC VARIABLES
            let caller:ContractAddress = get_caller_address();
            let current_user_margin:MarginState = self.userMargin.entry(caller).read();
            let pool:ERC4626ABIDispatcher = ERC4626ABIDispatcher { contract_address: self.pool.read()};
            let total_underlying_to_use:u256 = margin_amount_to_use * leverage.into();
            let available_margin:u256 = current_user_margin.total - current_user_margin.used; // @audit INVARIANT A should never be less than B
            let trading_pair:TradingPair = TradingPair { underlying_asset: self.underlying_asset.read(), traded_asset:token };
            // get hash for token trading pair 
            let base:felt252 = Bounded::<u128>::MAX.into();
            let hash:felt252 = PedersenTrait::new(base).update_with(trading_pair).finalize(); // @dev@TODO check what is the base parameter to make sure what is doing

            // checks
            assert!(available_margin >= margin_amount_to_use, "USER HAS NOT ENOUGH MARGIN DEPOSITED"); // the user has enough margin 
            assert!(pool.total_assets()>=total_underlying_to_use, "NOT ENOUGH LIQUIDITY ON THE POOL"); // the available liquidity on the pool is enough to cover the leverage requierement
            // assert!(trading pair is whitelisted ) @TODO
            
            // 2. SWAP LOGIC
            let mut counter_price:u256 = 0;
            let mut total_counter = 0; // obtained or "selled" depending on direction

            match direction {
                Direction::bullish => {
                    // If direction is bullish, perform a swap "underlying->counter"
                    counter_price = 1000000_u256; // simulate result for unit counter price calculation -> this is used to store the Position on the correspondant price range 
                    total_counter = 10000000_u256; // simulate 10 counter tokens was buyed
                },
                Direction::bearish => {
                    // IF direction is bearish, then do not perform the swap, just fetch the price and set apart the correspondant underlying to rebuy the asset when close the position
                    // (this is equivalent to swap the counter for the underlying to go short)
                    // @dev when close the position, we will buy the counter token and give it back to the trader, so -> the part the protocol keeps should be swaped to underlying 
                    // @dev should we still make a swap? because the user should deposit or directly transfer the counter they want to sell. OR we just take the equivalent from the deposited margin in underlying? so if they wants to get rid of his counter, they have to swap it and then deposit it here? if choose this last option, we should abstract that swap logic directly -> like give the options "use margin" or "deposit counter" -> this could be made on the front? or it's better to embed on this function as receive a paramenter to choose? or create another specific function follwing DRY principle?
                    counter_price = 1000000_u256;  
                    total_counter = 10000000_u256; 
                }
            }

            // 3. REGISTER ON STATE
            // setup position  
            let position:Position = Position {
                isOpen: true,
                virtualIndexOnPositionsOpen: self.positionsOpen.entry(hash).len(), // len()==currentIndex+1 (indexes from 0)
                virtualIndexOnPositionsOpenByUser: self.positionsOpenByUser.entry(caller).len(),
                virtualIndexOnPositionsOpenByUserByTradingPair: self.positionsOpenByUserByTradingPair.entry(caller).entry(hash).len(),
                owner: caller, 
                leverage,
                total_underlying_used: total_underlying_to_use,  
                total_traded_assets: total_counter,  
                direction,
                pair: trading_pair,
                openPrice: counter_price
            };
            // setup margin 
            let new_user_margin = MarginState { total: current_user_margin.total, used: current_user_margin.used + margin_amount_to_use };
            
            // register on state 
            self.userMargin.entry(caller).write(new_user_margin); // register user margin
            // 
            let index_of_new_position = self.positions.entry(hash).len();
            self.positions.entry(hash).push(position); 
            self.positionsOpen.entry(hash).push(index_of_new_position);
            self.positionsOpenByUser.entry(caller).push(index_of_new_position);
            self.positionsOpenByUserByTradingPair.entry(caller).entry(hash).push(index_of_new_position);

            // emit event 
        }

        fn close_position(ref self: ContractState, positionIndex: u64, token: ContractAddress) {
            // assertions 
            let caller = get_caller_address();
            let hash:felt252 = self.get_trading_pair_hash(token); 
            let position = self.positions.entry(hash).at(positionIndex); 
            assert!(position.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
            assert!(position.isOpen.read(), "CAN NOT CLOSE A NOT OPEN POSITION");

            // remove
            self._remove_position_from_view(super::View::positions, positionIndex, token); 
            self._remove_position_from_view(super::View::positionsByUser, positionIndex, token); 
            self._remove_position_from_view(super::View::positionsByUserByTradingPair, positionIndex, token); 
            
        }
    
    }    

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        
        fn _remove_position_from_view(ref self: ContractState, view:super::View,  positionIndex:u64, token:ContractAddress) {
            // basic variables
            let caller: ContractAddress = get_caller_address();
            let hash:felt252 = self.get_trading_pair_hash(token);

            // get position to be closed 
            let mut position_to_close = self.positions.entry(hash).at(positionIndex);

            // get views 
            let viewToUse = match view {
                super::View::positions => self.positionsOpen.entry(hash),
                super::View::positionsByUser => self.positionsOpenByUser.entry(caller),
                super::View::positionsByUserByTradingPair => self.positionsOpenByUserByTradingPair.entry(caller).entry(hash)
            };

            let viewToUseClosed = match view {
                super::View::positions => self.positionsClosed.entry(hash),
                super::View::positionsByUser => self.positionsClosedByUser.entry(caller),
                super::View::positionsByUserByTradingPair => self.positionsClosedByUserByTradingPair.entry(caller).entry(hash)
            };

            let remove_index:u64 = match view {
                super::View::positions => position_to_close.virtualIndexOnPositionsOpen.read(), 
                super::View::positionsByUser => position_to_close.virtualIndexOnPositionsOpenByUser.read(),
                super::View::positionsByUserByTradingPair => position_to_close.virtualIndexOnPositionsOpenByUserByTradingPair.read()
            };

            // change removed position state 
            position_to_close.isOpen.write(false);
            position_to_close.virtualIndexOnPositionsOpen.write(0);
            position_to_close.virtualIndexOnPositionsOpenByUser.write(0);
            position_to_close.virtualIndexOnPositionsOpenByUserByTradingPair.write(0);
            // self.positions.entry(hash).at(positionIndex).write(position_to_close);

            // removing Position from view and updating moved one 
            let latest_position_open_index = viewToUse.at(viewToUse.len()).read() - 1;
            
            let mut position: Position = self.positions.entry(hash).at(latest_position_open_index).read();
            position.virtualIndexOnPositionsOpen = remove_index;
            self.positions.entry(hash).at(latest_position_open_index).write(position);
            
            viewToUse.at(remove_index).write(latest_position_open_index);
            viewToUse.pop().unwrap();
            viewToUseClosed.push(positionIndex);
        }

        fn get_trading_pair_hash(self:@ContractState, token: ContractAddress) -> felt252 {
            let trading_pair:TradingPair = TradingPair { underlying_asset: self.underlying_asset.read(), traded_asset:token };
            PedersenTrait::new(Bounded::<u128>::MAX.into()).update_with(trading_pair).finalize()
        }

    }


}





// /// Remove from each correspondant view/state by using swap and remove algo 
//         /// 1. get latest position on the view 
//         /// 2. get such position from the positions vec
//         /// 3. update the position with the new correspondant virtual values
//         /// this has to be done for each view because the latest position for each one of this should be different
//         fn _remove_position_from_view(ref self: ContractState, view:super::View,  positionIndex:u64, token:ContractAddress) {
//             let caller: ContractAddress = get_caller_address();
//             let trading_pair:TradingPair = TradingPair { underlying_asset: self.underlying_asset.read(), traded_asset:token };
//             let base:felt252 = Bounded::<u128>::MAX.into();
//             let hash:felt252 = PedersenTrait::new(base).update_with(trading_pair).finalize(); 

//             // get position to be closed 
//             let mut position_to_close = self.positions.entry(hash).at(positionIndex);
//             let view_to_use = self.positionsOpen.entry(hash);
//             view_to_use.at(1).write(2);

//             assert!(position_to_close.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
//             match view {
//                 super::View::positions => {
//                     let remove_index:u64 = position_to_close.virtualIndexOnPositionsOpen.read();
//                     let latest_position_open_index = self.positionsOpen.entry(hash).at(self.positionsOpen.entry(hash).len()).read() - 1;
//                     let mut position: Position = self.positions.entry(hash).at(latest_position_open_index).read();
//                     position.virtualIndexOnPositionsOpen = remove_index;
//                     self.positions.entry(hash).at(latest_position_open_index).write(position);
//                     self.positionsOpen.entry(hash).at(remove_index).write(latest_position_open_index);
//                     self.positionsOpen.entry(hash).pop().unwrap();
//                     self.positionsClosed.entry(hash).push(positionIndex);
//                 },
//                 super::View::positionsByUser => {
//                     let remove_index:u64 = position_to_close.virtualIndexOnPositionsOpenByUser.read();
//                     let latest_position_open_by_client_index = self.positionsOpenByUser.entry(caller).at(self.positionsOpenByUser.entry(caller).len()).read() - 1;
//                     let mut position: Position = self.positions.entry(hash).at(latest_position_open_by_client_index).read();
//                     position.virtualIndexOnPositionsOpenByUser = remove_index;
//                     self.positions.entry(hash).at(latest_position_open_by_client_index).write(position);
//                     self.positionsOpenByUser.entry(caller).at(remove_index).write(latest_position_open_by_client_index);
//                     self.positionsOpenByUser.entry(caller).pop().unwrap();
//                     self.positionsClosedByUser.entry(caller).push(positionIndex);
//                 },
//                 super::View::positionsByUserByTradingPair => {
//                     let remove_index:u64 = position_to_close.virtualIndexOnPositionsOpenByUserByTradingPair.read();
//                     let latest_position_open_by_client_by_trading_pair_index = self.positionsOpenByUserByTradingPair.entry(caller).entry(hash).at(self.positionsOpenByUser.entry(caller).len()).read() - 1;
//                     let mut position: Position = self.positions.entry(hash).at(latest_position_open_by_client_by_trading_pair_index).read();
//                     position.virtualIndexOnPositionsOpenByUserByTradingPair = remove_index;
//                     self.positions.entry(hash).at(latest_position_open_by_client_by_trading_pair_index).write(position);
//                     self.positionsOpenByUserByTradingPair.entry(caller).entry(hash).at(remove_index).write(latest_position_open_by_client_by_trading_pair_index);
//                     self.positionsOpenByUserByTradingPair.entry(caller).entry(hash).pop().unwrap();
//                     self.positionsClosedByUserByTradingPair.entry(caller).entry(hash).push(positionIndex);
//                 },
//             }
//         }