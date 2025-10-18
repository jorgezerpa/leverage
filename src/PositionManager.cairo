// Internals 
// calculate_required_margin 

/// Simple contract for managing balance.
#[starknet::contract]
mod PositionManager {

    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::storage::{Vec, MutableVecTrait};

    // dispatchers
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_token::erc20::extensions::erc4626::interface::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};
    // 

    use leverage::Interfaces::PositionManager::{IPositionManager, View};
    use leverage::Interfaces::Shared::{Direction, MarginState, Position};
    use leverage::Interfaces::Adapters::EkuboAMMMarginTradingAdapter::{IEkuboAMMMarginTradingAdapterDispatcher,IEkuboAMMMarginTradingAdapterDispatcherTrait};
    use leverage::Interfaces::Pool::{IPoolDispatcher, IPoolDispatcherTrait};

    const POSITIONS_VECTOR_KEY: felt252 = 0;
    

    #[storage]
    struct Storage {
        admin: ContractAddress, // Multisig wallet at the beggining, then maybe could be a DAO
        adapter: ContractAddress,
        pool: ContractAddress, // lending pool -> Pool contract 
        poolUsedUnderlying: u256, // the amount of underlying that is actually covering a position (AKA lended) -> this should be substracted from pool balance for calculations 
        userMargin: Map<ContractAddress, MarginState>, // deposited and used margin for each user
        positions: Vec<Position>, // length ONLY INCREASES 
        positionsOpen: Map<felt252,Vec<u64>>, // the map has a single key -> POSITIONS_VECTOR_KEY, this is for return type matching during match sentences btw position and positions by user (one is a direct vector, the other is a pointer to the vector)
        positionsClosed: Map<felt252,Vec<u64>>,  
        positionsOpenByUser: Map<ContractAddress, Vec<u64>>, // User->positions 
        positionsClosedByUser: Map<ContractAddress, Vec<u64>>, // Historical purposes only -> added when liquidates or closes
        adapterTradeData: Map<u64, Vec<felt252>> // positionId->tradeData // used to store extra data that could return a third party protocol -> it is an array of felts, to decode it into actual types, you can call adapter.get_trade_data_types 
    }

     ////////////////////
    /// CONSTRUCTOR
    ////////////////////
    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
    ) {
        self.admin.write(admin);

        // set the first position index to a empty position -> when a position is closed or liquidated, view pointers will point to this index 
        let position:Position = Position {
            isOpen: false,
            virtualIndexOnPositionsOpen: 0, 
            virtualIndexOnPositionsOpenByUser: 0,
            owner:'0'_felt252.try_into().unwrap(), 
            leverage: 0,
            total_underlying_used: 0,  
            total_traded_assets: 0,  
            direction: Direction::bullish,
            openPrice: 0
        };
        
        self.positions.push(position); 
    }


    #[abi(embed_v0)]
    impl PositionManagerImpl of IPositionManager<ContractState> {
        /// GETTERS
        fn get_user_margin_state(self: @ContractState, address: ContractAddress) -> MarginState {
            self.userMargin.entry(address).read()
        }

        // @dev@todo implement calculation, this will be used by another functions too
        fn get_position_health(self: @ContractState, positionIndex:u64) -> u256 {
            10_u256
        }

        fn get_positions(self: @ContractState, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                array.append(self.positions[index].read());
            };

            array
        }
        
        fn get_position_from_view(self: @ContractState, indexes:Array<u64>) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();
    
            for index in indexes {
                array.append(self.positions[index].read());
            };
    
            array
        }

        fn get_positions_open(self: @ContractState, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsOpen.entry(POSITIONS_VECTOR_KEY)[index].read();
                array.append(self.positions[positionIndex].read());
            };

            array
        }

        fn get_positions_closed(self: @ContractState, from:u64, to: u64) -> Array<Position> {
            let mut array: Array<Position> = ArrayTrait::new();

            for index in from..to {
                let positionIndex = self.positionsClosed.entry(POSITIONS_VECTOR_KEY)[index].read();
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

        fn get_trade_data(self:@ContractState, positionIndex:u64) -> Array<felt252> {
            let mut data = ArrayTrait::<felt252>::new();
            let positionTradeData = self.adapterTradeData.entry(positionIndex);
            let numberOfItems:u64 = positionTradeData[0].read().try_into().unwrap(); // panics if conversion is not possible //  @audit Compiler does not allow to call .len(), so this is a temporary solution, not hte most secure 

            for i in 0..numberOfItems { 
                data.append(positionTradeData[i].read());
            }
            
            data
        }

        fn get_pool(self: @ContractState) -> ContractAddress {
            self.pool.read()
        }
        fn get_adapter(self: @ContractState) -> ContractAddress {
            self.adapter.read()
        }
        fn get_admin(self: @ContractState) -> ContractAddress {
            self.admin.read()
        }
        
        

        ////
        fn deposit_margin(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            // register depositor
            let newMarginState:MarginState = MarginState { total: amount, used: 0 };
            self.userMargin.entry(caller).write(newMarginState);
            
            // get funds
            let pool:ERC4626ABIDispatcher = ERC4626ABIDispatcher { contract_address: self.pool.read()};
            let token = ERC20ABIDispatcher { contract_address: pool.asset() };
            let success = token.transfer_from(caller, self.pool.read(), amount);
            
            assert!(success, "FAILED TRANSFER_FROM");
            // assert!(new balance - prev balance is equal to amount)
            
        }
        

        fn open_position(ref self: ContractState, margin_amount_to_use: u256, leverage: u8, direction: Direction, data:Array<felt252>){
            // 1. BASIC VARIABLES
            let caller:ContractAddress = get_caller_address();
            let current_user_margin:MarginState = self.userMargin.entry(caller).read();
            let pool:ERC4626ABIDispatcher = ERC4626ABIDispatcher { contract_address: self.pool.read()};
            let total_underlying_to_use:u256 = margin_amount_to_use * leverage.into();
            let available_margin:u256 = current_user_margin.total - current_user_margin.used; // @audit INVARIANT A should never be less than B

            // checks
            assert!(available_margin >= margin_amount_to_use, "USER HAS NOT ENOUGH MARGIN DEPOSITED"); // the user has enough margin 
            assert!(pool.total_assets()>=total_underlying_to_use, "NOT ENOUGH LIQUIDITY ON THE POOL"); // the available liquidity on the pool is enough to cover the leverage requierement
            // assert!(leverage is a valid multiplier);
            

            // 2. trade with adapter @audit possible vul not follow CEI
            let pool = IPoolDispatcher{contract_address: self.pool.read()};
            pool.transfer_assets_to_trade(total_underlying_to_use, self.adapter.read());
            
            let adapter = IEkuboAMMMarginTradingAdapterDispatcher{ contract_address: self.adapter.read() };
            let mut array: Array<felt252> = ArrayTrait::new();
            // @todo use returned data in a event or store it in position data, etc
            let (traded_asset_price, total_traded_asset, trade_data) = adapter.trade(total_underlying_to_use, direction, array); // This should -> swap tokens on ekubo, return the price of the individual traded asset value, and the total traded asset buyed 

            // 3. REGISTER ON STATE
            // setup position  
            let position:Position = Position {
                isOpen: true,
                virtualIndexOnPositionsOpen: self.positionsOpen.entry(POSITIONS_VECTOR_KEY).len(), // len()==currentIndex+1 (indexes from 0)
                virtualIndexOnPositionsOpenByUser: self.positionsOpenByUser.entry(caller).len(),
                owner: caller, 
                leverage,
                total_underlying_used: total_underlying_to_use,  
                total_traded_assets: total_traded_asset,  
                direction,
                openPrice: traded_asset_price
            };

            // setup margin 
            let new_user_margin = MarginState { total: current_user_margin.total, used: current_user_margin.used + margin_amount_to_use };
            
            // register on state 
            self.userMargin.entry(caller).write(new_user_margin); // register user margin
            // 
            let index_of_new_position = self.positions.len();
            self.positions.push(position); 
            self.positionsOpen.entry(POSITIONS_VECTOR_KEY).push(index_of_new_position);
            self.positionsOpenByUser.entry(caller).push(index_of_new_position);
            //
            let adapterTradeDataVec = self.adapterTradeData.entry(index_of_new_position);
            for item in trade_data {
                adapterTradeDataVec.push(item);
            }

            // emit event 
        }

        fn close_position(ref self: ContractState, positionIndex: u64) {
            //1. assertions 
            let caller = get_caller_address();
            let position = self.positions.at(positionIndex); 
            assert!(position.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
            assert!(position.isOpen.read(), "CAN NOT CLOSE A NOT OPEN POSITION");
            // Check:
            // health of position to check if can close it or needs to deposit collateral first 
            // in case of loss -> how much should protocol keep from margin to cover losses (in case of loss)
            // in case of profit -> how much should the procol take on fees 
            // how much should send to the user 

            // 2. adapter calls @audit possible vul not follow CEI
            let adapter = IEkuboAMMMarginTradingAdapterDispatcher{ contract_address: self.adapter.read() };
            adapter.untrade(positionIndex); //  -> performs close position logic, like -> swaps, execute options or futures, etc

            // @INVARIANT close a position should always finish with non-traded-assets and only underlaying asset
            //  -> will transfer value to THIS so we can perform validations -> @dev todo should calculate a expected amount and return if it was not achieved? -> like a pre-calc and a slippage tolerance?

            // 3. make correspondant transfers  
            // for trader, for pool and for protocol 

            // 4. STATE UPDATES
            self._remove_position_from_view(View::positions, positionIndex); 
            self._remove_position_from_view(View::positionsByUser, positionIndex); 

            // modify margin state 

            // emit event
        }

        fn liquidate_position(ref self: ContractState, positionIndex: u64) {
            // 1. assertions 
            let caller = get_caller_address();
            let position = self.positions.at(positionIndex); 
            assert!(position.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
            assert!(position.isOpen.read(), "CAN NOT CLOSE A NOT OPEN POSITION");
            // check:
            // health state -> can be liquidated?
            // calculate -> how much back to the pool, how much as protocol fees
            
            // make correspondant transfers -> follow CEI, do it bellow removes 
            // 3. adapter.untrade(position)

            // STATE UPDATE
            self._remove_position_from_view(View::positions, positionIndex); 
            self._remove_position_from_view(View::positionsByUser, positionIndex); 

            // modify margin state 

            // emit event
        }
    
        // ADMIN
        fn set_pool(ref self: ContractState, pool_address: ContractAddress) {
            assert!(self.admin.read() == get_caller_address(), "ONLY ADMIN");
            self.pool.write(pool_address);
        }

        fn set_adapter(ref self: ContractState, pool_address: ContractAddress) {
            assert!(self.admin.read() == get_caller_address(), "ONLY ADMIN");
            self.adapter.write(pool_address);
        }


    }    

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        
        fn _remove_position_from_view(ref self: ContractState, view:View,  positionIndex:u64) {
            // basic variables
            let caller: ContractAddress = get_caller_address();

            // get position to be closed 
            let mut position_to_close = self.positions.at(positionIndex);

            // search for the position on the specified view and get data needed to remove such position
            let (remove_index, viewToUse, viewToUseClosed) = match view {
                View::positions => (position_to_close.virtualIndexOnPositionsOpen.read(),self.positionsOpen.entry(POSITIONS_VECTOR_KEY),self.positionsClosed.entry(POSITIONS_VECTOR_KEY)), 
                View::positionsByUser => (position_to_close.virtualIndexOnPositionsOpenByUser.read(),self.positionsOpenByUser.entry(caller),self.positionsClosedByUser.entry(caller)),
            };
        
            // change removed position state on positions Vec 
            position_to_close.isOpen.write(false);
            position_to_close.virtualIndexOnPositionsOpen.write(0);
            position_to_close.virtualIndexOnPositionsOpenByUser.write(0);

            // Get latest position on the view
            let latest_position_open_index = viewToUse.at(viewToUse.len()-1).read();
            let mut latest_position = self.positions.at(latest_position_open_index);
            
            // update latest position pointers to the new position on the view
            match view {
                View::positions => latest_position.virtualIndexOnPositionsOpen.write(remove_index), 
                View::positionsByUser => latest_position.virtualIndexOnPositionsOpenByUser.write(remove_index), 
            };
            
            // replace position to remove with latest position and then pop and add latest to history 
            viewToUse.at(remove_index).write(latest_position_open_index);
            viewToUse.pop().unwrap();
            viewToUseClosed.push(positionIndex);
        }

    }


}
