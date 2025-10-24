Leverage Protocol: A Composable, Undercollateralized Margin Framework for Starknet
Author(s): Jorge Zerpa
Version: 0.1.0
Date: October 14, 2025

Abstract
The Leverage Protocol is a decentralized, non-custodial liquidity protocol on the Starknet ecosystem designed to facilitate undercollateralized lending for the purpose of margin trading. It provides a unified margin framework that allows traders to open leveraged long or short positions across a wide array of integrated third-party DeFi protocols. By abstracting capital sourcing from trade execution, the protocol enhances capital efficiency and unlocks novel trading strategies. The architecture is centered around two core components: an ERC-4626 compliant Liquidity Pool for capital provision and a PositionManager smart contract that serves as a transparent, on-chain broker for trade execution and position tracking. This paper outlines the protocol's architecture, core mechanics, risk parameters, and its potential to augment the composability of the Starknet DeFi landscape.

1. Introduction

Starknet has a diverse ecosystem of DeFi primitives, including Decentralized Exchanges (DEXs), derivatives platforms, and staking protocols. However, capital remains largely fragmented across these platforms, limiting the ability of traders to efficiently deploy leverage. Leverage Protocol addresses this inefficiency by introducing an on-chain, undercollateralized lending framework inspired by traditional margin trading systems.

The primary objective is to create a capital-efficient layer that aggregates liquidity and allows traders to utilize it to gain multiplied exposure in their positions on other DeFi protocols. Users deposit an initial margin, and the protocol provides the additional capital required to achieve the desired leverage, sourcing these funds from a common liquidity pool. This enables traders to amplify their trade exposure, using a fraction of the capital that would otherwise be required.

By acting as an integration layer, Leverage Protocol leverages the inherent composability of blockchain technology, allowing it to connect with any compliant third-party DeFi protocol to build enhanced and synergistic trading experiences.

2. System Architecture
The protocol's logic is encapsulated within a modular architecture, with primary smart contracts instantiated for each unique trading pair and integration (e.g., USDT/wBTC on Ekubo). This deployment strategy effectively isolates risk between different asset markets and external protocols.

2.1 Liquidity Pool
The Pool contract is the liquidity backbone of the protocol. It is a fully compliant implementation of the ERC-4626 Tokenized Vault Standard, which provides a robust and standardized interface for token deposits and withdrawals.

Liquidity Providers (LPs): LPs deposit the base asset (referred to as the "underlying" asset, typically a stablecoin like USDC or USDT) into the pool. In return, they receive tokenized shares representing their pro-rata claim on the pool's assets.

Yield Generation: LPs earn a variable yield generated from the interest and fees paid by traders who borrow funds from the pool to open leveraged positions.

Asset Management: The assets held within this vault are exclusively managed by the associated PositionManager contract to fund trades.

2.2 PositionManager
The PositionManager contract is the core operational engine of the protocol. It orchestrates all trading activities and is responsible for maintaining the solvency of the system. Its primary functions include:

Position Management: It handles the opening, closing, and modification of all trading positions. When a trader initiates a position, the PositionManager withdraws the required capital (trader's margin + borrowed funds) from the Liquidity Pool and executes the trade on the designated third-party protocol.

State Tracking: The contract maintains a comprehensive record of each position's state, including the margin amount, leverage ratio, entry price, and current debt.

On-Chain Broker: The PositionManager acts as a transparent and immutable broker. While it technically owns the position on the external protocol, the original trader retains full control over the position's lifecycle, with the ability to add margin, close the position, and realize profits or losses.

2.3 Integration Framework
The protocol is designed for extensibility through a modular integration framework. For each third-party protocol that is integrated, a new, specific instance of the PositionManager and a dedicated Adapter contract are deployed.

This adapter-based approach ensures that the core protocol logic remains secure and isolated. The Adapter contract is responsible for translating standardized commands from the PositionManager (e.g., executeTrade, closePosition) into the specific function calls and data structures required by the target protocol (e.g., Ekubo's swap function). This design allows for rapid and secure onboarding of new DeFi protocols, while containing the risks associated with any single integration to its specific set of contracts.

3. Core Mechanics & Position Lifecycle
3.1 Opening a Position
Margin Deposit: A trader initiates the process by depositing a specific amount of the underlying asset as margin into the PositionManager.

Trade Parameters: The trader specifies the asset to be traded, the direction (long or short), the desired leverage (e.g., 2x, 5x, 10x), and the target third-party protocol.

Execution: The PositionManager calculates the total required capital, borrows the necessary amount from the Pool, and executes the trade via the appropriate Adapter contract. The PositionManager then becomes the custodian of the resulting assets or position.

3.2 Position Health & Liquidation
The solvency of each position is determined by its Margin Ratio, which measures the current value of the trader's margin relative to its initial value. A drop in this ratio indicates a loss in the position.

Price Oracles: The protocol relies on real-time price data to calculate the current value of a position. This data is critical for monitoring the Margin Ratio. An off-chain keeper network fetches this data from reliable oracles and/or the integrated third-party protocol.

Thresholds: Each trading pair is configured with two key thresholds:

Margin Call Threshold: A warning level (e.g., when the Margin Ratio drops to 50%). At this point, the trader is notified that their position is approaching liquidation risk.

Liquidation Threshold: The point at which a position is deemed undercollateralized and can be forcefully closed (e.g., when the Margin Ratio drops to 20%). This ensures the protocol can repay its debt to the liquidity pool even in adverse market conditions.

Liquidation Trigger: The off-chain keeper network monitors the Margin Ratio of all open positions. If a position's ratio drops below the Liquidation Threshold, a keeper can trigger the liquidate() function in the PositionManager.

On-Chain Safeguards: The liquidate() function contains on-chain verifications that re-calculate the position's Margin Ratio using the asset price at the moment of execution. This prevents malicious or faulty liquidations, ensuring only genuinely unhealthy positions are liquidated.

Liquidation Process: Upon successful liquidation, the position is closed on the third-party protocol. The borrowed funds are repaid to the liquidity pool. A liquidation penalty is deducted from the trader's remaining margin, and this penalty is distributed to the liquidator and the LPs. Any final remaining collateral is returned to the trader.

3.3 Interest Rate & Fee Model
The protocol generates revenue for LPs and for its own treasury through a fee structure applied at the time a position is closed.

Traders pay two types of fees on their borrowed capital: a borrow fee and a profit-sharing fee.

The mathematical representation of the fees taken when a position is closed is as follows:

Let:

A_borrowed = The total amount of the underlying asset borrowed from the pool.

P_profit = The gross profit generated from the trade, where P_profit > 0.

F_borrow = The fixed borrow fee rate.

F_profit = The profit sharing fee rate.

The total fee paid by the trader (Fee_trader) is:
Fee_trader = (A_borrowed * F_borrow) + (max(0, P_profit) * F_profit)

A portion of this total fee is retained by the protocol treasury. The remainder is distributed to the Liquidity Pool as yield for LPs.

Let:

F_protocol = The protocol's percentage cut of the total fees.

The fee taken by the protocol (Fee_protocol_share) is:
Fee_protocol_share = Fee_trader * F_protocol

In the event of a liquidation, the trader's remaining margin is treated as profit for the liquidity pool, rewarding LPs for the associated risk.

4. Use Cases & Composability
The true power of the Leverage Protocol lies in its ability to interact with the broader Starknet DeFi ecosystem.

Leveraged Spot Trading: A trader can deposit 1,000 USDT as margin to execute a 5x leveraged long on wBTC. The protocol borrows an additional 4,000 USDT and executes a 5,000 USDT swap for wBTC on a DEX like Ekubo.

Leveraged Staking: A user can deposit ETH as margin to borrow additional ETH, staking the total amount in a liquid staking protocol to amplify their staking rewards.

Enhanced Derivatives Exposure: Traders can borrow assets to increase the size of their positions on derivatives or options protocols, allowing for more complex and capital-efficient hedging or speculative strategies.

5. Risk Analysis
A comprehensive understanding of the risks is paramount. Key risks include:

Third-Party Protocol Risk: As the protocol integrates with external DeFi platforms, it inherits the risks of those platforms. A vulnerability in an integrated DEX could lead to a loss of funds. Risk is mitigated by isolating integrations into separate contract instances.

Oracle Risk: The protocol's solvency depends on accurate and timely price data. A manipulated or lagging oracle could lead to improper liquidations. Mitigation involves using robust, decentralized oracle solutions.

Liquidity Risk: A sudden withdrawal of a large amount of capital by LPs could reduce the available funds for borrowing, potentially affecting traders' ability to open new positions.

6. Future Work
The initial release of Leverage Protocol serves as a foundational layer. The roadmap includes:

Integration with a wider range of Starknet DeFi protocols.

Support for multi-asset collateralization.

Development of a decentralized governance structure (DAO) to manage protocol parameters, risk settings, and new asset integrations.

Research into cross-chain margin trading capabilities.

7. Conclusion
Leverage Protocol introduces a fundamental financial primitive to the Starknet ecosystem, enabling undercollateralized lending for margin trading in a decentralized and composable manner. By creating a unified framework for leverage, the protocol enhances capital efficiency and empowers traders with more sophisticated tools. With a strong focus on security and modularity, Leverage Protocol is poised to become a core building block in the future of Starknet DeFi.