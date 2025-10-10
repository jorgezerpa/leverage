// Internals 
// calculate_required_margin 

/// Simple contract for managing balance.
#[starknet::contract]
mod PositionManager {

    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::pedersen::PedersenTrait;
    use core::num::traits::Bounded;
    
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::storage::{Vec, MutableVecTrait};

    // dispatchers
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_token::erc20::extensions::erc4626::interface::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};
    // 

    use leverage::Interfaces::PositionManager::{IPositionManager, View};
    use leverage::Interfaces::Shared::{Direction, MarginState, Position, TradingPair};
    

    #[storage]
    struct Storage {
        admin: ContractAddress, // Multisig wallet at the beggining, then maybe could be a DAO
        //
        underlying_asset: ContractAddress, // to do -> read this from pool, not store it here 
        pool: ContractAddress, // lending pool -> Pool contract 
        poolUsedUnderlying: u256, // the amount of underlying that is actually covering a position (AKA lended) -> this should be substracted from pool balance for calculations 
        userMargin: Map<ContractAddress, MarginState>, // deposited and used margin for each user
        // TradingPair->positions
        positions: Vec<Position>, // Only add, never remove AKA length ONLY INCREASES 
        positionsOpen: Map<felt252,Vec<u64>>, 
        positionsClosed: Map<felt252,Vec<u64>>,  
        positionsOpenByUser: Map<ContractAddress, Vec<u64>>, // User->positions 
        positionsClosedByUser: Map<ContractAddress, Vec<u64>>, // Historical purposes only -> added when liquidates or closes
        positionsOpenByUserByTradingPair: Map<ContractAddress, Map<felt252,Vec<u64>>>, // User->pair->positions 
        positionsClosedByUserByTradingPair: Map<ContractAddress, Map<felt252,Vec<u64>>>, // User->pair->positions 
        //
        tradingPairPools: Map<felt252, ContractAddress>,
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
        admin: ContractAddress,
        underlying_asset: ContractAddress,
        pool: ContractAddress,
    ) {
        self.admin.write(admin);
        self.underlying_asset.write(underlying_asset);
        self.pool.write(pool);
    }


    #[abi(embed_v0)]
    impl PositionManagerImpl of IPositionManager<ContractState> {
        /// GETTERS
        fn get_user_margin_state(self: @ContractState, address: ContractAddress) -> MarginState {
            self.userMargin.entry(address).read()
        }

        // @dev@todo implement calculation, this will be used by another functions too
        fn get_position_health(self: @ContractState, token: ContractAddress, positionIndex:u64) -> u256 {
            10_u256
        }

        fn get_positions(self: @ContractState, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                array.append(self.positions[index].read());
            };

            array
        }

        fn get_positions_open(self: @ContractState, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsOpen.entry(tradingPairHash)[index].read();
                array.append(self.positions[positionIndex].read());
            };

            array
        }

        fn get_positions_closed(self: @ContractState, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsClosed.entry(tradingPairHash)[index].read();
                array.append(self.positions[positionIndex].read());
            };

            array
        }

        fn get_positions_open_by_user(self: @ContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsOpenByUser.entry(user)[index].read();
                array.append(self.positions[positionIndex].read());
            };

            array
        }
        
        fn get_positions_closed_by_user(self: @ContractState, user: ContractAddress, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();
            
            for index in from..to {
                let positionIndex = self.positionsClosedByUser.entry(user)[index].read();
                array.append(self.positions[positionIndex].read());
            };
            
            array
        }
        
        fn get_positions_open_by_user_by_trading_pair(self: @ContractState, user: ContractAddress, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsOpenByUserByTradingPair.entry(user).entry(tradingPairHash)[index].read();
                array.append(self.positions[positionIndex].read());
            };

            array
        }

        fn get_positions_closed_by_user_by_trading_pair(self: @ContractState, user: ContractAddress, tradingPairHash: felt252, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsClosedByUserByTradingPair.entry(user).entry(tradingPairHash)[index].read();
                array.append(self.positions[positionIndex].read());
            };

            array
        }

        fn get_trading_pair_hash(self: @ContractState, token:ContractAddress) -> felt252 {
            self._get_trading_pair_hash(token)
        }
        
        //// ADMIN 
        
        /// @notice this functions can be used also to "pause|unpause" a trading pair trading 
        fn add_new_trading_pair_pool(ref self: ContractState, token: ContractAddress, pool: ContractAddress) {
            assert!(get_caller_address()==self.admin.read(), "ONLY ADMIN");
            let hash = self._get_trading_pair_hash(token);
            self.tradingPairPools.entry(hash).write(pool);            
        } 
        fn remove_trading_pair_pool(ref self: ContractState, token: ContractAddress) {
            assert!(get_caller_address()==self.admin.read(), "ONLY ADMIN");
            let hash = self._get_trading_pair_hash(token);
            let zero_address: ContractAddress = 0_felt252.try_into().unwrap();
            self.tradingPairPools.entry(hash).write(zero_address);
        }
        

        ////
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
            let index_of_new_position = self.positions.len();
            self.positions.push(position); 
            self.positionsOpen.entry(hash).push(index_of_new_position);
            self.positionsOpenByUser.entry(caller).push(index_of_new_position);
            self.positionsOpenByUserByTradingPair.entry(caller).entry(hash).push(index_of_new_position);

            // emit event 
        }

        fn close_position(ref self: ContractState, positionIndex: u64, token: ContractAddress) {
            // assertions 
            let caller = get_caller_address();
            let position = self.positions.at(positionIndex); 
            assert!(position.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
            assert!(position.isOpen.read(), "CAN NOT CLOSE A NOT OPEN POSITION");
            
            // Check:
            // health of position to check if can close it or needs to deposit collateral first 
            // in case of loss -> how much should protocol keep from margin to cover losses (in case of loss)
            // in case of profit -> how much should the procol take on fees 
            // how much should send to the user 

            // make correspondant transfers  -> follow CEI this after below removes 

            // remove
            self._remove_position_from_view(View::positions, positionIndex, token); 
            self._remove_position_from_view(View::positionsByUser, positionIndex, token); 
            self._remove_position_from_view(View::positionsByUserByTradingPair, positionIndex, token); 

            // modify margin state 

            // emit event
        }

        fn liquidate_position(ref self: ContractState, positionIndex: u64, token: ContractAddress) {
            // assertions 
            let caller = get_caller_address();
            let position = self.positions.at(positionIndex); 
            assert!(position.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
            assert!(position.isOpen.read(), "CAN NOT CLOSE A NOT OPEN POSITION");

            // check:
            // health state -> can be liquidated?
            // calculate -> how much back to the pool, how much as protocol fees
            
            // make correspondant transfers -> follow CEI, do it bellow removes 

            // remove
            self._remove_position_from_view(View::positions, positionIndex, token); 
            self._remove_position_from_view(View::positionsByUser, positionIndex, token); 
            self._remove_position_from_view(View::positionsByUserByTradingPair, positionIndex, token); 

            // modify margin state 

            // emit event
        }
    
    }    

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        
        fn _remove_position_from_view(ref self: ContractState, view:View,  positionIndex:u64, token:ContractAddress) {
            // basic variables
            let caller: ContractAddress = get_caller_address();
            let hash:felt252 = self._get_trading_pair_hash(token);

            // get position to be closed 
            let mut position_to_close = self.positions.at(positionIndex);

            // search for the position on the specified view and get data needed to remove such position
            let (remove_index, viewToUse, viewToUseClosed) = match view {
                View::positions => (position_to_close.virtualIndexOnPositionsOpen.read(),self.positionsOpen.entry(hash),self.positionsClosed.entry(hash)), 
                View::positionsByUser => (position_to_close.virtualIndexOnPositionsOpenByUser.read(),self.positionsOpenByUser.entry(caller),self.positionsClosedByUser.entry(caller)),
                View::positionsByUserByTradingPair => (position_to_close.virtualIndexOnPositionsOpenByUserByTradingPair.read(),self.positionsOpenByUserByTradingPair.entry(caller).entry(hash),self.positionsClosedByUserByTradingPair.entry(caller).entry(hash))
            };
        
            // change removed position state on positions Vec 
            position_to_close.isOpen.write(false);
            position_to_close.virtualIndexOnPositionsOpen.write(0);
            position_to_close.virtualIndexOnPositionsOpenByUser.write(0);
            position_to_close.virtualIndexOnPositionsOpenByUserByTradingPair.write(0);

            // Get latest position on the view
            let latest_position_open_index = viewToUse.at(viewToUse.len()-1).read();
            let mut latest_position = self.positions.at(latest_position_open_index);
            
            // update latest position pointers to the new position on the view
            match view {
                View::positions => latest_position.virtualIndexOnPositionsOpen.write(remove_index), 
                View::positionsByUser => latest_position.virtualIndexOnPositionsOpenByUser.write(remove_index), 
                View::positionsByUserByTradingPair => latest_position.virtualIndexOnPositionsOpenByUserByTradingPair.write(remove_index), 
            };
            
            // replace position to remove with latest position and then pop and add latest to history 
            viewToUse.at(remove_index).write(latest_position_open_index);
            viewToUse.pop().unwrap();
            viewToUseClosed.push(positionIndex);
        }

        fn _get_trading_pair_hash(self:@ContractState, token: ContractAddress) -> felt252 {
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
//         fn _remove_position_from_view(ref self: ContractState, view:View,  positionIndex:u64, token:ContractAddress) {
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
//                 View::positions => {
//                     let remove_index:u64 = position_to_close.virtualIndexOnPositionsOpen.read();
//                     let latest_position_open_index = self.positionsOpen.entry(hash).at(self.positionsOpen.entry(hash).len()).read() - 1;
//                     let mut position: Position = self.positions.entry(hash).at(latest_position_open_index).read();
//                     position.virtualIndexOnPositionsOpen = remove_index;
//                     self.positions.entry(hash).at(latest_position_open_index).write(position);
//                     self.positionsOpen.entry(hash).at(remove_index).write(latest_position_open_index);
//                     self.positionsOpen.entry(hash).pop().unwrap();
//                     self.positionsClosed.entry(hash).push(positionIndex);
//                 },
//                 View::positionsByUser => {
//                     let remove_index:u64 = position_to_close.virtualIndexOnPositionsOpenByUser.read();
//                     let latest_position_open_by_client_index = self.positionsOpenByUser.entry(caller).at(self.positionsOpenByUser.entry(caller).len()).read() - 1;
//                     let mut position: Position = self.positions.entry(hash).at(latest_position_open_by_client_index).read();
//                     position.virtualIndexOnPositionsOpenByUser = remove_index;
//                     self.positions.entry(hash).at(latest_position_open_by_client_index).write(position);
//                     self.positionsOpenByUser.entry(caller).at(remove_index).write(latest_position_open_by_client_index);
//                     self.positionsOpenByUser.entry(caller).pop().unwrap();
//                     self.positionsClosedByUser.entry(caller).push(positionIndex);
//                 },
//                 View::positionsByUserByTradingPair => {
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