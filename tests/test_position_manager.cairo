use starknet::ContractAddress;
use core::serde::Serde;
use core::num::traits::Pow;

use snforge_std::{
    declare, 
    ContractClassTrait, 
    DeclareResultTrait,
    start_cheat_caller_address,
    stop_cheat_caller_address,
    Token, 
    CustomToken,
    set_balance
};

use leverage::Interfaces::Shared::{Direction, MarginState, Position};
use leverage::Interfaces::PositionManager::{IPositionManagerDispatcher, IPositionManagerDispatcherTrait};
use leverage::Interfaces::Pool::{IPoolDispatcher, IPoolDispatcherTrait};
use leverage::Interfaces::Adapters::AdapterBase::{IAdapterBaseDispatcher, IAdapterBaseDispatcherTrait};
//
use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

fn ADMIN() -> ContractAddress {
    'admin'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'user1'.try_into().unwrap()
}

fn WAD() -> u256 {
    10_u256.pow(18)
}

fn deploy_contract(name: ByteArray, constructor_params: Array<felt252>) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_params).unwrap();
    contract_address
}

fn setup() -> (IPositionManagerDispatcher, IPoolDispatcher, IAdapterBaseDispatcher, ERC20ABIDispatcher)
{
    // deploy ERC20 that will be used as underlaying
    let mut array = ArrayTrait::new();
    let name:ByteArray = "LEVERAGE POOL TOKEN";
    let symbol:ByteArray = "LPT";
    name.serialize(ref array);
    symbol.serialize(ref array);
    let token = ERC20ABIDispatcher { contract_address: deploy_contract("MockERC20", array.clone()) };
    
    // deploy position manager
    let mut array = ArrayTrait::new();
    ADMIN().serialize(ref array);
    let positionManager = IPositionManagerDispatcher { contract_address: deploy_contract("PositionManager", array.clone()) };
    
    // deploy pool
    let mut array = ArrayTrait::new();
    let name:ByteArray = "LEVERAGE POOL TOKEN";
    let symbol:ByteArray = "LPT";
    name.serialize(ref array);
    symbol.serialize(ref array);
    token.contract_address.serialize(ref array);
    positionManager.contract_address.serialize(ref array);
    let pool = IPoolDispatcher { contract_address: deploy_contract("Pool", array.clone()) };
    
    // deploy adapter
    let mut array: Array<felt252> = ArrayTrait::new();
    positionManager.contract_address.serialize(ref array);
    
    let adapter = IAdapterBaseDispatcher { contract_address: deploy_contract("MockTradingAdapter", array.clone()) };

    // update pool on PositionManager
    start_cheat_caller_address(positionManager.contract_address, ADMIN());
    positionManager.set_pool(pool.contract_address);
    positionManager.set_adapter(adapter.contract_address);
    stop_cheat_caller_address(positionManager.contract_address);

    // giving tokens to users
    let cheated_token = Token::Custom(
        CustomToken {
            contract_address: token.contract_address,
            balances_variable_selector: selector!("ERC20_balances")
        }
    );
    set_balance(USER_1(), 100*WAD(), cheated_token);

    (
        positionManager,
        pool,
        adapter,
        token
    )
}

#[test]
fn test_deploy() {
    let (positionManager, pool, adapter, _) = setup();

    // check initial state
    assert(positionManager.get_admin()==ADMIN(), 'Incorrect admin');
    assert(positionManager.get_pool()==pool.contract_address, 'Incorrect pool');
    assert(positionManager.get_adapter()==adapter.contract_address, 'Incorrect adapter');
    
    // check creation of empty position on index 0
    let mut indexes = ArrayTrait::<u64>::new();
    indexes.append(0);
    let positions = positionManager.get_position_from_view(indexes);
    let position = *positions.at(0);

    assert(!position.isOpen, 'Position should be closed');
    assert(position.virtualIndexOnPositionsOpen==0, 'should be 0');
    assert(position.virtualIndexOnPositionsOpenByUser==0, 'should be 0');
    assert(position.owner=='0'_felt252.try_into().unwrap(), 'should be 0');
    assert(position.leverage==0, 'should be 0');
    assert(position.total_underlying_used==0, 'should be 0');
    assert(position.total_traded_assets==0, 'should be 0');
    assert(position.direction==Direction::bullish, 'should be bullish');
    assert(position.openPrice==0, 'should be 0');
}

#[test]
fn test_deposit_margin() {
    let (positionManager, _, _, token) = setup();

    let margin_to_deposit = 1*WAD();

    start_cheat_caller_address(token.contract_address, USER_1());
    token.approve(positionManager.contract_address, margin_to_deposit);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.deposit_margin(margin_to_deposit);
    stop_cheat_caller_address(positionManager.contract_address);

    let margin = positionManager.get_user_margin_state(USER_1());
    assert(margin.total==margin_to_deposit, 'Incorrect total margin');
    assert(margin.used==0, 'Incorrect used margin');
}

#[test]
fn test_withdraw_margin() {
    let (positionManager, _, _, token) = setup();

    deposit_margin(positionManager, token, USER_1(), 10*WAD());

    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.withdraw_margin(10*WAD());
    stop_cheat_caller_address(positionManager.contract_address);
}

#[test]
fn test_open_position() {
    let (positionManager, _, _, token) = setup();

    deposit_margin(positionManager, token, USER_1(), 10*WAD());
    
    let margin_amount_to_use:u256 = 1*WAD();
    let leverage: u8 = 2;
    let direction = Direction::bullish; 
    let data:Array<felt252> = ArrayTrait::new();

    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.open_position(margin_amount_to_use, leverage, direction, data);
    stop_cheat_caller_address(positionManager.contract_address);

    // assert position state 
    let userOpenPositions = positionManager.get_positions_open_by_user(USER_1(), 0, 1);
    let position = *userOpenPositions.at(0);

    assert(position.isOpen, 'position not open');
    assert(position.virtualIndexOnPositionsOpen==0, 'incorrect index');
    assert(position.virtualIndexOnPositionsOpenByUser==0, 'incorrect index');
    assert(position.owner==USER_1(), 'incorrect owner');
    assert(position.leverage==leverage, 'incorrect leverage');
    assert(position.total_underlying_used==margin_amount_to_use*leverage.into(), 'incorrect underl. used');
    assert(position.total_traded_assets==0, 'incorrect traded'); // the '0' is harcoded on the mock adapter, just to confirm that the value is being correctly setted, with a reeal adapter we should implement a different logic
    assert(position.openPrice==0, 'should be 0'); // the '0' is harcoded on the mock adapter, just to confirm that the value is being correctly setted, with a reeal adapter we should implement a different logic
    assert(position.direction==direction, 'should be bullish'); 

    let userOpenPositionsIndexes = positionManager.get_indexes_of_positions_open_by_user(USER_1(), 0, 1);
    let openPositionIndex = *userOpenPositionsIndexes.at(0);
    let trade_data = positionManager.get_trade_data(openPositionIndex);
    assert(trade_data.len()==1, 'incorrect trade data length');
    assert(*trade_data.at(0)==1, 'incorrect length element'); // even if theres no data, first element should be 1 (aka the length of the array inclusive)
}

#[test]
fn test_close_position() {
    let (positionManager, _, _, token) = setup();
    deposit_margin(positionManager, token, USER_1(), 10*WAD());
    // Opening position 
    let margin_amount_to_use:u256 = 1*WAD();
    let leverage: u8 = 2;
    let direction = Direction::bullish; 
    let data:Array<felt252> = ArrayTrait::new();
    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.open_position(margin_amount_to_use, leverage, direction, data);
    stop_cheat_caller_address(positionManager.contract_address);
    
    // getting position index
    let userOpenPositions = positionManager.get_indexes_of_positions_open_by_user(USER_1(), 0, 1);
    let openPositionIndex = *userOpenPositions.at(0);
    
    // closing position 
    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.close_position(openPositionIndex);
    stop_cheat_caller_address(positionManager.contract_address);
    
    // checking state 
    let userClosedPositions = positionManager.get_indexes_of_positions_closed_by_user(USER_1(), 0, 1);
    let closedPositionIndex = *userClosedPositions.at(0);
    let closedPosition = *positionManager.get_positions_closed_by_user(USER_1(), 0, 1).at(0);
    
    assert(userClosedPositions.len()==1, 'not added to closed positions');
    assert(openPositionIndex==closedPositionIndex, 'incorrect position closed');

    // should register all as it was, but change it to isClosed -> @audit should I limit to pass it to true again? for extra sec
    assert(!closedPosition.isOpen, 'position not open');
    assert(closedPosition.owner==USER_1(), 'incorrect owner');
    assert(closedPosition.leverage==leverage, 'incorrect leverage');
    assert(closedPosition.total_underlying_used==margin_amount_to_use*leverage.into(), 'incorrect underl. used');
    assert(closedPosition.total_traded_assets==0, 'incorrect traded'); // the '0' is harcoded on the mock adapter, just to confirm that the value is being correctly setted, with a reeal adapter we should implement a different logic
    assert(closedPosition.openPrice==0, 'should be 0'); // the '0' is harcoded on the mock adapter, just to confirm that the value is being correctly setted, with a reeal adapter we should implement a different logic
    assert(closedPosition.direction==direction, 'should be bullish'); 
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_should_remove_position_from_open_after_remove() {
    let (positionManager, _, _, token) = setup();
    
    deposit_margin(positionManager, token, USER_1(), 10*WAD());
    
    // Opening position 
    let margin_amount_to_use:u256 = 1*WAD();
    let leverage: u8 = 2;
    let direction = Direction::bullish; 
    let data:Array<felt252> = ArrayTrait::new();
    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.open_position(margin_amount_to_use, leverage, direction, data);
    stop_cheat_caller_address(positionManager.contract_address);
    
    // getting position index
    let userOpenPositions = positionManager.get_indexes_of_positions_open_by_user(USER_1(), 0, 1);
    let openPositionIndex = *userOpenPositions.at(0);
    
    // closing position 
    start_cheat_caller_address(positionManager.contract_address, USER_1());
    positionManager.close_position(openPositionIndex);
    stop_cheat_caller_address(positionManager.contract_address);
    
    // try to get open positions should fail out of bounds
    positionManager.get_indexes_of_positions_open_by_user(USER_1(), 0, 1);
}

#[test]
fn test_liquidate_position() {
    // let (positionManager, _, _, token) = setup();
    // deposit_margin(positionManager, token, USER_1(), 10*WAD());
    // // Opening position 
    // let margin_amount_to_use:u256 = 1*WAD();
    // let leverage: u8 = 2;
    // let direction = Direction::bullish; 
    // let data:Array<felt252> = ArrayTrait::new();
    // start_cheat_caller_address(positionManager.contract_address, USER_1());
    // positionManager.open_position(margin_amount_to_use, leverage, direction, data);
    // stop_cheat_caller_address(positionManager.contract_address);
    
    // // getting position index
    // let userOpenPositions = positionManager.get_indexes_of_positions_open_by_user(USER_1(), 0, 1);
    // let openPositionIndex = *userOpenPositions.at(0);
    
    // // LIQUIDATE
    // positionManager.close_position(openPositionIndex);

}

#[test]
fn test_get_position_health() {

}

#[test]
fn test_get_trade_data() {

}

#[test]
fn test_set_pool() {}
#[test]
fn test_set_adapter() {}
#[test]
fn test_set_pool_only_owner() {}
#[test]
fn test_set_adapter_only_owner() {}



// HELPERS 
fn deposit_margin(positionManager: IPositionManagerDispatcher, token: ERC20ABIDispatcher, user:ContractAddress, margin_to_deposit:u256) {
    start_cheat_caller_address(token.contract_address, user);
    token.approve(positionManager.contract_address, margin_to_deposit);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(positionManager.contract_address, user);
    positionManager.deposit_margin(margin_to_deposit);
    stop_cheat_caller_address(positionManager.contract_address);
}