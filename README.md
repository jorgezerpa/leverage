# Leverage Protocol: A Composable, Undercollateralized Margin Framework for Starknet 

Leverage Protocol is a **decentralized** liquidity protocol on the Starknet ecosystem designed to facilitate undercollateralized lending for the purpose of margin trading. 

It provides a unified margin framework that allows traders to open leveraged long or short positions across a wide array of integrated third-party DeFi protocols. 

The basic architecture of the project is centered around two core components: an **ERC-4626 compliant Liquidity Pool** for capital provision and a **`PositionManager` smart contract** that serves as a transparent, on-chain broker for trade execution and position tracking.

**These core contracts are 'plugged-in' to adapter contracts**, that act as bridges between Leverage Protocol and any other Starknet DeFi protocol and Dapp. 

To get a more detailed view of the protocol, please read our [whitepaper](link)


---
## Installation guide
First, **download this repo to your local machine** and move into it.

Then, check your tools version: 
- Run `scarb --version`; it should return `scarb 2.12.0`, `cairo 2.12.0`, and `sierra 1.7.0`. If not, check the [official Starknet setup guide](https://docs.starknet.io/build/quickstart/environment-setup).
- Verify the correct Starknet Foundry version by running `snforge --version`; it should be `snforge 0.48.1`. If not, you can follow the [official Starknet Foundry setup guide](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html).

Once you have the correct tools, you can run `scarb build` to compile the project, `scarb test` to run the test suites, and any other command available. 


---
## Contributor guide
The Leverage Protocol is in active development and looking for contributors. Feel free to get into the issues section and submit a PR. Of course, you can create an issue if you find some error, there's something you want to build, or you have an idea to improve the protocol. 

**Before contributing**, you should read the **whitepaper** of the project so you understand what it is and can make better contributions. 

---
## Project main files 
`Pool.cairo`
- Follows the ERC4626 standard. 
- Is the contract that holds the **LPs' underlying funds**, the underlying margin deposited by traders, and (if necessary) the counter/quote asset of the trade.
- The funds utilization is managed **ONLY** by the `PositionManager` contract, which has the ability to transfer the pool's holded tokens to any address.  

`PositionManager.cairo`
- This is the **heart** of the protocol. It works as a **decentralized** broker that **manages** trading positions. 
- A trader can deposit/withdraw margin, open/close positions, deposit margin calls, and check position state and history via this contract. 
- A **keeper** can constantly monitor the **position state** to liquidate them or close them when **it's** necessary via this contract. 
- Is the only authorized entity to utilize `Pool.cairo` funds. 

`Interfaces/AdapterBase.cairo`
- In simple terms, an adapter is a contract that acts as a bridge between the `PositionManager` and a third-party DeFi protocol. 
- This file contains a primary interface that any adapter contract should implement. It has the functions that the `PositionManager` contract will call to interact with the adapter to open and close positions using third-party protocols. 
- **Notice:** An adapter **HAS** to implement this interface, but the logic implemented on each function can and must be customized to the related **third-party** protocol. Also, extra interfaces or traits can be implemented to add extra functionalities specific to the adapter implementation (like view functions or internal state modifiers). The storage of this adapter contract is also a whiteboard to write custom logic.
- Actually there is a `mockAdapter` contract used on the tests, a contributor can modify it or create a new file from it if consider that is useful for the development. 
- All adapters must be into the `Adapters` module. 

All the other files on the project are type files or helpers like math libraries or test helpers. 

## Happy coding!
![Keep Starknet Free](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExa2RqMnUwaWF2cm02MXp5dGVldzJia3dsZ2JpdGQzZHhscDQ4aXkxbSZlcD12MV9naWZzX3NlYXJjaCZjdD1n/O1AkPwu1MqGokR7IFx/giphy.gif)