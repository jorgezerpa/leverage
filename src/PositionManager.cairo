// Internals 
// calculate_required_margin 

/// Simple contract for managing balance.
#[starknet::contract]
mod PositionManager {

    use openzeppelin_token::erc20::extensions::erc4626::interface::IERC4626Dispatcher;
    use openzeppelin_token::erc20::interface::IERC20Dispatcher;
    use core::num::traits::Pow;
    use leverage::Maths::Math;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::storage::{Vec, MutableVecTrait};

    // dispatchers
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_token::erc20::extensions::erc4626::interface::{ERC4626ABIDispatcher, ERC4626ABIDispatcherTrait};
    // 

    use leverage::Interfaces::PositionManager::{IPositionManager, View};
    use leverage::Interfaces::Shared::{Direction, MarginState, Position};
    use leverage::Interfaces::Adapters::AdapterBase::{IAdapterBaseDispatcher,IAdapterBaseDispatcherTrait};
    use leverage::Interfaces::Pool::{IPoolDispatcher, IPoolDispatcherTrait};

    const ADDRESS_ZERO: ContractAddress = 0x0.try_into().unwrap(); 
    const POSITIONS_VECTOR_KEY: felt252 = 0;
    const FEE_BPS: u8 = 10; // 0.1%
    const PROTOCOL_FEE_BPS: u8 = 10; // 0.1% this will be taken from the X% of total fees 
    const BPS: u32 = 10000; // 0.1%
    

    #[storage]
    struct Storage {
        admin: ContractAddress, // Multisig wallet at the beggining, then maybe could be a DAO
        fee_recipient: ContractAddress, // set to 0 address to disable protocol fees 
        adapter: ContractAddress,
        pool: ContractAddress, // lending pool -> Pool contract 
        poolUsedUnderlying: u256, // the amount of underlying that is actually covering a position (AKA lended) -> this should be substracted from pool balance for calculations 
        userMargin: Map<ContractAddress, MarginState>, // deposited and used margin for each user
        positionsCount: u64,
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
            owner:ADDRESS_ZERO, 
            leverage: 0,
            total_underlying_used: 0,  
            total_traded_assets: 0,  
            direction: Direction::bullish,
            openPrice: 0
        };
        
        self.positions.push(position); 
        self.positionsCount.write(1);
    }


    #[abi(embed_v0)]
    impl PositionManagerImpl of IPositionManager<ContractState> {
        /// GETTERS
        
        fn get_positions_count(self: @ContractState) -> u64 {
            self.positionsCount.read()
        }

        fn get_user_margin_state(self: @ContractState, address: ContractAddress) -> MarginState {
            self.userMargin.entry(address).read()
        }

        // @dev@todo implement calculation, this will be used by another functions too
        fn get_position_health(self: @ContractState, positionIndex:u64) -> u256 {
            IAdapterBaseDispatcher { contract_address: self.adapter.read() }.calculate_health(positionIndex)
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
        
        fn get_indexes_of_positions_open_by_user(self: @ContractState, user: ContractAddress, from:u64, to: u64) -> Array<u64> {
            let mut array: Array<u64> = ArrayTrait::new();
            
            for index in from..to {
                array.append(self.positionsOpenByUser.entry(user)[index].read());
            };
            
            array
        }

        fn get_indexes_of_positions_closed_by_user(self: @ContractState, user: ContractAddress, from:u64, to: u64) -> Array<u64> {
            let mut array: Array<u64> = ArrayTrait::new();
            
            for index in from..to {
                array.append(self.positionsClosedByUser.entry(user)[index].read());
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
            // @dev@todo add min amount check 

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

        fn withdraw_margin(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let marginState = self.userMargin.entry(caller).read();
            let availableToWithdraw = marginState.total - marginState.used; // @INVARIANT used should never be more than totoal  

            assert!(availableToWithdraw>=amount, "Exceed available margin to withdraw");

            self.userMargin.entry(caller).write(MarginState { used: marginState.used, total: marginState.total - amount }); // safe operation 

            let pool:ERC4626ABIDispatcher = ERC4626ABIDispatcher { contract_address: self.pool.read()};
            let token = ERC20ABIDispatcher { contract_address: pool.asset() };

            let pool = IPoolDispatcher{contract_address: self.pool.read()};
            pool.transfer_assets_to_trade(amount, get_contract_address());

            token.transfer(caller, amount);

            // emit event 

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
            // @todo assert!(leverage is a valid multiplier);
            

            // 2. trade with adapter @audit possible vul not follow CEI
            let pool = IPoolDispatcher{contract_address: self.pool.read()};
            pool.transfer_assets_to_trade(total_underlying_to_use, self.adapter.read());
            
            let adapter = IAdapterBaseDispatcher{ contract_address: self.adapter.read() };
            let (traded_asset_price, total_traded_asset, trade_data) = adapter.trade(total_underlying_to_use, direction, data); // This should -> swap tokens on ekubo, return the price of the individual traded asset value, and the total traded asset buyed 

            // 3. REGISTER ON STATE
            // setup position  
            let index_of_new_position = self.positions.len();
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
            self.positions.push(position); 
            self.positionsOpen.entry(POSITIONS_VECTOR_KEY).push(index_of_new_position);
            self.positionsOpenByUser.entry(caller).push(index_of_new_position);
            //
            let adapterTradeDataVec = self.adapterTradeData.entry(index_of_new_position);
            for item in trade_data {
                adapterTradeDataVec.push(item);
            }

            self.positionsCount.write( self.positionsCount.read() + 1 );

            // emit event 
        }

        fn close_position(ref self: ContractState, positionIndex: u64) {
            // 0. basic vars
            let caller = get_caller_address();
            let position = self.positions.at(positionIndex); 
            let adapter = IAdapterBaseDispatcher { contract_address: self.adapter.read() };
            let pool:ERC4626ABIDispatcher = ERC4626ABIDispatcher { contract_address: self.pool.read()};
            let underlaying_token = ERC20ABIDispatcher { contract_address: pool.asset() };
            let marginState = self.userMargin.entry(caller).read();
            
            //1. assertions 
            assert!(position.owner.read()==caller, "ONLY OWNER CAN CLOSE POSITION");
            assert!(position.isOpen.read(), "CAN NOT CLOSE A NOT OPEN POSITION");
            assert!(!adapter.is_liquidable(positionIndex), "CAN NOT CLOSE A LIQUIDABLE POSITION"); // @dev this is preventing front-running of liquidate function 

            // 2. Untrade @audit not follow CEI, but it is needed to untrade first to know the exact amount of tokens we have back -> So @todo@IMPORTANT implement reentrancy checks 
            let adapter = IAdapterBaseDispatcher{ contract_address: self.adapter.read() };
            adapter.untrade(positionIndex); // @dev this should snapshot prev and post balance and work with difference -> preventing any kind of donation attack
            // FROM NOW, this contract holds the underlaying tokens (margin + borrowed funds) that was backing the position

            // 3. Evaluate P&L and act in consequence
            // the next 3 variables are in underlaying terms 
            let current_position_value = adapter.get_current_position_value(positionIndex);
            
            let initial_position_value = position.total_underlying_used.read();
            
            if(current_position_value > initial_position_value){ // in profit -> take fees and add profit to user margin register. 
                let net_profit = current_position_value - initial_position_value;
                let fees = Math::mulDiv(net_profit, FEE_BPS.into(), BPS.into(), 18); // @todo harcoded decimals, must fetch some how -> in this case, fetch the erc20 function
                let trader_profit = net_profit - fees; // rest

                // X percent of fees, the other goes to the pool 
                let protocol_fee = Math::mulDiv(fees, PROTOCOL_FEE_BPS.into(), BPS.into(), 18);

                if self.fee_recipient.read() != ADDRESS_ZERO {
                    underlaying_token.transfer(self.fee_recipient.read(), protocol_fee);
                }
                
                // user profit is deposited on its margin -> @todo@dev create a function that allows user to partially retire unused margin 
                self.userMargin.entry(caller).write( 
                    MarginState { 
                        total: marginState.total + trader_profit, 
                        used: marginState.used - position.total_underlying_used.read()/position.leverage.read().into() // substract used margin from used 
                    }
                );
            } 
            else { // in loss -> how much should take from margin to cover losses
                // calculate total loss in underlying terms 
                let net_loss = initial_position_value - current_position_value;
                let fees = Math::mulDiv(net_loss, FEE_BPS.into(), BPS.into(), 18); // taking fee from loss -> this will be added to the amount to be deducted from user  
 
                if(net_loss < position.total_underlying_used.read()/position.leverage.read().into()) { // if loss is less than margin
                    self.userMargin.entry(caller).write(
                        MarginState {
                            total: marginState.total - (net_loss + fees), // @OSS report highlighter bug -> "a - b + c" != "a - (b+c)"
                            used: marginState.used - position.total_underlying_used.read()/position.leverage.read().into()
                        }
                    );
                    let protocol_fee = Math::mulDiv(fees, PROTOCOL_FEE_BPS.into(), BPS.into(), 18);

                    if self.fee_recipient.read() != ADDRESS_ZERO {
                        underlaying_token.transfer(self.fee_recipient.read(), protocol_fee);
                    }
                }
                else { // if loss is more or equal to margin
                    // @notice this code should never be executed, because to keeper will liquidate the position before reaching a state where the net loss is more than the underlaying backing the loan (including fees)
                    // BUT, there could be some weird edge cases (like keeper fails or extreme traded asset volatility) that causes the loss to be greater than the backup token amount
                    // In such cases, the "if" code would fail due to underflow, which will cause a DoS on this function and possibly funds freezing
                    // to handle that, the else block is taking all the position' collateral to minimiza AMAP the protocol losses NOT protocol fees are taken
                    self.userMargin.entry(caller).write(
                        MarginState {
                            total: marginState.total - position.total_underlying_used.read()/position.leverage.read().into(),
                            used: marginState.used - position.total_underlying_used.read()/position.leverage.read().into()
                        }
                    );
                }
            }

            // 4. Transfer remaining underlaying back to the pool -> not invariant, but should always increase the pool balance compared with pre-position 
            underlaying_token.transfer(self.pool.read(), underlaying_token.balanceOf(get_contract_address()));

            // 4. STATE UPDATES
            self._remove_position_from_view(View::positions, positionIndex); 
            self._remove_position_from_view(View::positionsByUser, positionIndex); 

            // emit event
        }

        //  CLOSE POSITION SHOULD BE SIMILAR TO THIS -> but calculations change based on profit/loss state 
        // @audit Not follow CEI -> refactor or implement pertinent security checks (reentrancy guards, etc)
        fn liquidate_position(ref self: ContractState, positionIndex: u64) {
            let position = self.positions.at(positionIndex); 
            let adapter = IAdapterBaseDispatcher { contract_address: self.adapter.read() };
            let pool:ERC4626ABIDispatcher = ERC4626ABIDispatcher { contract_address: self.pool.read()};
            let underlaying_token = ERC20ABIDispatcher { contract_address: pool.asset() };
            let marginState = self.userMargin.entry(position.owner.read()).read();
            
            // 1. assertions 
            assert!(position.isOpen.read(), "CAN NOT LIQUIDATE A NOT OPEN POSITION");
            assert!(adapter.is_liquidable(positionIndex), "POSITION NOT LIQUIDABLE");
            
            // 2. Untrade -> close position on 3rd party protocol and send underlaying to this contract
            adapter.untrade(positionIndex); //  -> performs close position logic, like -> swaps, execute options or futures, etc -> tranfers amount back to this contract -> @dev@todo@audit should confirm/assert this
            
            // 3. calculate underlaying distribution
            let currentBalance = underlaying_token.balance_of(get_contract_address()); // assuming contract should not hold any underlaying asset, and any direct transfer is considered a "donation" // @audit this could be dangerous? what if someone transfer a lot of tokens? via flashloan for example? could break something?
            
            // take protocol fee
            if self.fee_recipient.read() != ADDRESS_ZERO {
                let protocol_fee = Math::mulDiv(currentBalance, FEE_BPS.into(), BPS.into(), 18); // in liquidations protocol takes more % of fees than in close, because all the other value will be directly transfered to the pool as profit for LPs
                underlaying_token.transfer(self.fee_recipient.read(), protocol_fee);
            }

            // transfer remainder back to the pool as profit
            underlaying_token.transfer(self.pool.read(), underlaying_token.balance_of(get_contract_address()));

            // STATE UPDATE
            self._remove_position_from_view(View::positions, positionIndex); 
            self._remove_position_from_view(View::positionsByUser, positionIndex); 

            // modify margin state
            let newTotal = marginState.total - (position.total_underlying_used.read()/position.leverage.read().into()); // substract all the margin that was used to back the position
            let newUsed = marginState.used - (position.total_underlying_used.read()/position.leverage.read().into());

            self.userMargin.entry(position.owner.read()).write(MarginState { total: newTotal, used: newUsed });            

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
            // get position to be closed 
            let mut position_to_close = self.positions.at(positionIndex);

            // search for the position on the specified view and get data needed to remove such position
            let (remove_index, viewToUse, viewToUseClosed) = match view {
                View::positions => (position_to_close.virtualIndexOnPositionsOpen.read(),self.positionsOpen.entry(POSITIONS_VECTOR_KEY),self.positionsClosed.entry(POSITIONS_VECTOR_KEY)), 
                View::positionsByUser => (position_to_close.virtualIndexOnPositionsOpenByUser.read(),self.positionsOpenByUser.entry(position_to_close.owner.read()),self.positionsClosedByUser.entry(position_to_close.owner.read())),
            };
        
            // change removed position state on positions Vec 
            position_to_close.isOpen.write(false);
            // position_to_close.virtualIndexOnPositionsOpen.write(0);
            // position_to_close.virtualIndexOnPositionsOpenByUser.write(0);

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


// function calculate_health(uint256 positionId) 
//         public 
//         view 
//         returns (uint256 healthFactor) 
//     {
//         Position storage pos = positions[positionId];

//         // 1. Fetch current price of the asset held in the position.
//         // Assumes a successful price fetch. Error handling (e.g., `try/catch`) would be crucial in production.
//         uint256 currentPrice = oracle.getAssetPrice(pos.assetAddress);

//         // 2. Calculate the Current Position Value (Value of the asset held after the trade)
//         // Value = Quantity * Price (scaled by an internal precision factor)
//         // Note: A real implementation must handle price and quantity scaling carefully to prevent overflow/underflow.
//         // Assuming assetQuantity and currentPrice are scaled by 1e18, we divide by 1e18 to get the scaled value.
//         uint256 currentPositionValue = (pos.assetQuantity * currentPrice) / DENOMINATOR_PRECISION;

//         // 3. Calculate the Total Debt Obligation
//         // Total Debt = Principal Borrowed Amount + Accrued Interest + Any accrued Fees/Borrow Costs
//         // For simplicity, we assume interestAccrued already includes any relevant fees.
//         uint256 totalDebt = pos.borrowedAmount + pos.interestAccrued;

//         // 4. Calculate the Margin Ratio (Health Factor)
//         // Margin Ratio = (Current Position Value * DENOMINATOR_PRECISION) / Total Debt Obligation
//         // We multiply the numerator by DENOMINATOR_PRECISION to maintain the precision of the result.
//         // Prevents division by zero: if totalDebt is 0, the position is unleveraged and extremely healthy (return max uint).
//         if (totalDebt == 0) {
//             return type(uint256).max;
//         }

//         healthFactor = (currentPositionValue * DENOMINATOR_PRECISION) / totalDebt;

//         return healthFactor;
//     }
