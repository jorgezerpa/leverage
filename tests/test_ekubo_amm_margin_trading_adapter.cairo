// use starknet::ContractAddress;
// use core::serde::Serde;

// use snforge_std::{
//     declare, 
//     ContractClassTrait, 
//     DeclareResultTrait,
//     start_cheat_caller_address,
//     stop_cheat_caller_address,
// };

// use leverage::Interfaces::Shared::{Direction, MarginState, Position};
// use leverage::Interfaces::PositionManager::{IPositionManagerDispatcher, IPositionManagerDispatcherTrait};
// use leverage::Interfaces::Pool::{IPoolDispatcher, IPoolDispatcherTrait};
// // to do create a mock adapter first 
// use leverage::Mock::MockTradingAdapter::{IMockTradingAdapterDispatcher, IMockTradingAdapterDispatcherTrait};

// fn ADMIN() -> ContractAddress {
//     'admin'.try_into().unwrap()
// }

// fn ADAPTER() -> ContractAddress {
//     'adapter'.try_into().unwrap()
// }

// fn POOL() -> ContractAddress {
//     'pool'.try_into().unwrap()
// }

// fn UNDERLAYING_ASSET() -> ContractAddress {
//     'ERC20'.try_into().unwrap()
// }



// fn deploy_contract(name: ByteArray, constructor_params: Array<felt252>) -> ContractAddress {
//     let contract = declare(name).unwrap().contract_class();
//     let (contract_address, _) = contract.deploy(@constructor_params).unwrap();
//     contract_address
// }

// fn setup() -> (IPositionManagerDispatcher, IPoolDispatcher, IMockTradingAdapterDispatcher)
// {
//     // deploy position manager
//     let mut array = ArrayTrait::new();
//     ADMIN().serialize(ref array);
//     let positionManager = IPositionManagerDispatcher { contract_address: deploy_contract("PositionManager", array.clone()) };
    
//     // deploy pool
//     let mut array = ArrayTrait::new();
//     let name:ByteArray = "LEVERAGE POOL TOKEN";
//     let symbol:ByteArray = "LPT";
//     name.serialize(ref array);
//     symbol.serialize(ref array);
//     UNDERLAYING_ASSET().serialize(ref array);
//     positionManager.contract_address.serialize(ref array);
//     let pool = IPoolDispatcher { contract_address: deploy_contract("Pool", array.clone()) };
    
//     // deploy adapter
//     let mut array: Array<felt252> = ArrayTrait::new();
//     positionManager.contract_address.serialize(ref array);
    
//     let adapter = IMockTradingAdapterDispatcher { contract_address: deploy_contract("MockTradingAdapter", array.clone()) };

//     // update pool on PositionManager
//     start_cheat_caller_address(positionManager.contract_address, ADMIN());
//     positionManager.set_pool(pool.contract_address);
//     stop_cheat_caller_address(positionManager.contract_address);

//     (
//         positionManager,
//         pool,
//         adapter
//     )
// }

// #[test]
// fn test_deploy() {
//     let (positionManager, pool, adapter) = setup();

//     // let dispatcher = IHelloStarknetDispatcher { contract_address };

//     // let balance_before = dispatcher.get_balance();
//     // assert(balance_before == 0, 'Invalid balance');

//     // dispatcher.increase_balance(42);

//     // let balance_after = dispatcher.get_balance();
//     // assert(balance_after == 42, 'Invalid balance');
// }

// // #[test]
// // #[feature("safe_dispatcher")]
// // fn test_cannot_increase_balance_with_zero_value() {
// //     let contract_address = deploy_contract("HelloStarknet");

// //     let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

// //     let balance_before = safe_dispatcher.get_balance().unwrap();
// //     assert(balance_before == 0, 'Invalid balance');

// //     match safe_dispatcher.increase_balance(0) {
// //         Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
// //         Result::Err(panic_data) => {
// //             assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
// //         }
// //     };
// // }
