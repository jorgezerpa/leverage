// use starknet::{ContractAddress};
use leverage::Interfaces::Shared::{Direction};

#[starknet::interface]
pub trait IEkuboAMMMarginTradingAdapter<TContractState> {
    fn trade(ref self: TContractState, amount: u256, direction: Direction, data: Array<felt252>) -> (u256, u256, Array<felt252>); // return unit price and total acquired traded asset
    fn untrade(ref self: TContractState, position_index: u64);
    fn get_trade_data_types(self: @TContractState) -> Array<felt252>;
    fn set_trade_data_types(ref self: TContractState, types: Array<felt252>); // ONLY ADMIN
}

        // fn _calculate_health(
        //     adapter: IAdapterBaseDispatcher,
        //     position: Position
        // ) -> u256 {
        //     // 1. Fetch current price of the asset held in the position.
        //     let currentTradedAssetPrice = 100; // adapter.getPrice or something -> in UNDERLAYING terms/decimals

        //     // 2. Calculate the Current Position Value (Value of the asset held after the trade)
        //     // Value = Quantity * Price (scaled by an internal precision factor)
        //     // @note implementation must handle price and quantity scaling carefully to prevent overflow/underflow.
        //     // Assuming assetQuantity and currentPrice are scaled by 1e18, we divide by 1e18 to get the scaled value.
        //     let DENOMINATOR = 1000000000000000000; // @TODO calculate the correct denominator -> the result should be in underlaying decimals 
        //     let currentPositionValue = (position.total_traded_assets * currentTradedAssetPrice) / DENOMINATOR;
            
        //     // 3. Calculate the Total Debt Obligation
        //     // Total Debt = Principal Borrowed Amount + Accrued Interest + Any accrued Fees/Borrow Costs
        //     // For simplicity, we assume interestAccrued already includes any relevant fees.
        //     let initialPositionValue = position.total_underlying_used;
        //     // @TODO let totalDebt = position.total_underlaying_used + interests_accrued (if any) +/- diff btw current and initial position value
        //     let totalDebt = initialPositionValue;

        //     // 4. Calculate the Margin Ratio (Health Factor)
        //     // Prevents division by zero: if totalDebt is 0, the position is unleveraged and extremely healthy (return a max unit).
        //     if (totalDebt == 0) {
        //         return 9999;
        //     }
        //     let healthFactor = (currentPositionValue * DENOMINATOR) / totalDebt; 

        //     return healthFactor;
        // }


