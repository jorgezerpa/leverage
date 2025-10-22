pub mod Math {
    // =========================================================================
    // 1. OPERATIONS WITH SAME DECIMALS (Standard Fixed-Point)
    // =========================================================================

    // @notice Multiplies two values (A and B) that are both scaled by the same decimals.
    // @dev A' * B' = (A * decimals) * (B * decimals) = (A * B) * 1e(decimals*2).
    // To correct the scaling back to decimals, we must divide by decimals.
    // Result = (A' * B') / decimals.
    // @param a The first term.
    // @param b The second term.
    // @param decimals The decimals at which a and b are scaled.
    // @return The product, also scaled by WAD.
    // 
    pub fn mul(a:u256, b:u256, decimals:u256) -> u256 {
        return a * b / decimals;
    }

    // @notice Divides two values (A and B) that are both scaled by decimals.
    // @dev A' / B' = (A * decimals) / (B * decimals). The decimals factors cancel out, leading
    // to truncation in integer arithmetic.
    // To maintain decimal precision in the result, the numerator (A') must be
    // pre-scaled by decimals before division.
    // Result = (A' * decimals) / B'.
    // @param a The numerator .
    // @param b The denominator.
    // @param decimals the decimals.
    // @return The quotient, scaled by decimals.
    // 
    pub fn div(a:u256, b:u256, decimals:u256) -> u256 {
        return a * decimals / b;
    }

    // =========================================================================
    // 2. OPERATIONS WITH DIFFERENT DECIMALS
    // =========================================================================
    
    // @notice Multiplies two values with different decimal scales (e.g., 18 and 6 decimals).
    // @dev The resulting product of the underlying integers is scaled by (10^N_A * 10^N_B).
    // To get the target decimal precision (N_target), we must divide by 10^(N_A + N_B - N_target).
    // Here, we calculate the required division factor (DECIMALS_A_POWER_OF_10 / DECIMALS_B_POWER_OF_10) 
    // to correct the scaling.
    // * @param a The first term (e.g., ETH amount, scaled by DECIMALS_A_POWER_OF_10).
    // @param b The second term (e.g., USDT amount, scaled by DECIMALS_B_POWER_OF_10).
    // @param decimalsAPowerOf10 The 10^N factor for term A (e.g., WAD for 18 decimals).
    // @param decimalsBPowerOf10 The 10^N factor for term B (e.g., DECIMALS_6 for 6 decimals).
    // @param targetDecimalsPowerOf10 The 10^N factor for the desired output precision (e.g., WAD for 18 decimals).
    // @return The product, scaled by targetDecimalsPowerOf10.
    // 
    pub fn mulDifferentDecimals(
        a: u256,
        b:u256,
        decimalsAPowerOf10:u256,
        decimalsBPowerOf10:u256,
        targetDecimalsPowerOf10:u256
    ) -> u256 {
        // Handle complex case where target is neither A nor B's decimals. 
        // This is complex and usually avoided -> (10^(N_A + N_B)) / 10^(N_target)
        // For simplicity (AND SECURITY), we stick to the common scenario where target = N_A or N_B
        assert!(targetDecimalsPowerOf10==decimalsAPowerOf10 || targetDecimalsPowerOf10==decimalsBPowerOf10, "Unsupported Target Decimals");

        // The combined scaling of a*b is (decimalsAPowerOf10 * decimalsBPowerOf10).
        // We need to divide this by targetDecimalsPowerOf10.
        // Division Factor = (decimalsAPowerOf10 * decimalsBPowerOf10) / targetDecimalsPowerOf10
            
        // This calculation is safer:
        // (a * b) / (Division Factor) because (a*b) > (division factor) -> is bigger enough to keep precision 

        // Correction Factor (how much to divide the product by to get the target scale)
        // If Target Decimals = N_A, then factor is DECIMALS_B_POWER_OF_10
        // If Target Decimals = N_B, then factor is DECIMALS_A_POWER_OF_10
            
        // Let's assume the target scale is the largest scale for simpler code
        let mut correctionFactor: u256 = 
            if(targetDecimalsPowerOf10 == decimalsAPowerOf10) { decimalsBPowerOf10 } 
            else { decimalsAPowerOf10 };
            
        return a * b / correctionFactor;
    }

    // @notice Divides two values with different decimal scales (A / B) and returns the result
    // at the desired target decimal precision (N_target).
    // @dev The ratio A'/B' is scaled by 10^(N_A - N_B).
    // To correct the scaling to 10^N_target, we must multiply the ratio by 10^(N_target - (N_A - N_B)).
    // This is equivalent to pre-scaling the numerator A' by 10^(N_target - N_A) and 
    // the denominator B' by 10^(0 - N_B).
    // * The most robust way is to pre-scale the division by the factor 
    // 10^(N_target) / (10^N_A / 10^N_B) = 10^(N_target - N_A + N_B).
    // * @param a The numerator (scaled by DECIMALS_A_POWER_OF_10).
    // @param b The denominator (scaled by DECIMALS_B_POWER_OF_10).
    // @param decimalsAPowerOf10 The 10^N factor for term A (e.g., WAD for 18 decimals).
    // @param decimalsBPowerOf10 The 10^N factor for term B (e.g., DECIMALS_6 for 6 decimals).
    // @param targetDecimalsPowerOf10 The 10^N factor for the desired output precision.
    // @return The quotient, scaled by targetDecimalsPowerOf10.
    //
    pub fn divDifferentDecimals(
        a: u256,
        b: u256,
        decimalsAPowerOf10: u256,
        decimalsBPowerOf10: u256,
        targetDecimalsPowerOf10: u256
    ) -> u256 {
        // Correction Factor = (targetDecimalsPowerOf10 * decimalsBPowerOf10) / decimalsAPowerOf10
        // We use this factor to pre-scale the numerator 'a' to maintain precision.

        let correctionFactor = targetDecimalsPowerOf10 * decimalsBPowerOf10 / decimalsAPowerOf10;
            
        // Result = (a * CorrectionFactor) / b
        return a * correctionFactor / b;
    }

    // @notice Computes (a * b) / c, maintaining decimals precision in the result.
    // @dev The operation is equivalent to (a * b / c) * decimals.
    // This is the common pattern for calculating a share or fraction with fixed-point numbers.
    // @param a The first term
    // @param b The second term
    // @param c The divisor
    // @param decimals
    // @return The quotient, scaled by WAD.
    pub fn mulDiv(
        a:u256, 
        b:u256, 
        c:u256,
        decimals: u256
    ) -> u256 {
        // We want to compute: (a * b) / c * WAD.
        // To maintain precision and avoid integer truncation before the final division,
        // we must multiply the numerator (a * b) by WAD before dividing by c.
        // Result = (a * b) * WAD / c.
        
        // NOTE: This simple implementation is prone to a severe overflow if (a * b)
        // exceeds the maximum value of a uint256 (2^256 - 1). 
        // In production code, one should use a safer, assembly-based mulDiv, 
        // or ensure (a * b) / c is the intended WAD-scale operation (which is (a * b) / (c / WAD) 
        // but c is also WAD scaled).
        
        // Sticking to the simple, but risky, fixed-point logic implied by the existing library:
        return div(mul(a,b,decimals), c, decimals);
     
    }

}


// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// /**
//  * @title FixedMath
//  * @notice Library for common fixed-point arithmetic operations in Solidity.
//  * We assume a standard fixed decimal precision of 18 (like Ether/DAI).
//  * The values passed (uint256) are always the underlying integer amounts.
//  */
// library FixedMath {
//     // Standard decimal precision used for most ERC20 tokens (e.g., ETH, DAI)
//     // 10**18 (1 followed by 18 zeros)
//     uint256 internal constant WAD = 1e18; 
    
//     // Constant for 6 decimals (e.g., USDC, USDT)
//     // 10**6 (1 followed by 6 zeros)
//     uint256 internal constant DECIMALS_6 = 1e6;

//     // =========================================================================
//     // 1. OPERATIONS WITH SAME DECIMALS (Standard Fixed-Point)
//     // =========================================================================

//     /**
//      * @notice Multiplies two values (A and B) that are both scaled by WAD (1e18).
//      * @dev A' * B' = (A * 1e18) * (B * 1e18) = (A * B) * 1e36.
//      * To correct the scaling back to 1e18, we must divide by 1e18.
//      * Result = (A' * B') / WAD.
//      * @param a The first term (scaled by WAD).
//      * @param b The second term (scaled by WAD).
//      * @return The product, also scaled by WAD.
//      */
//     function mul(uint256 a, uint256 b) internal pure returns (uint256) {
//         return a * b / WAD;
//     }

//     /**
//      * @notice Divides two values (A and B) that are both scaled by WAD (1e18).
//      * @dev A' / B' = (A * 1e18) / (B * 1e18). The 1e18 factors cancel out, leading
//      * to truncation in integer arithmetic.
//      * To maintain WAD precision in the result, the numerator (A') must be
//      * pre-scaled by WAD before division.
//      * Result = (A' * WAD) / B'.
//      * @param a The numerator (scaled by WAD).
//      * @param b The denominator (scaled by WAD).
//      * @return The quotient, scaled by WAD.
//      */
//     function div(uint256 a, uint256 b) internal pure returns (uint256) {
//         // This explicitly scales 'a' by WAD to maintain precision (your requested third point)
//         return a * WAD / b;
//     }
    
//     // =========================================================================
//     // 2. OPERATIONS WITH DIFFERENT DECIMALS
//     // =========================================================================

//     /**
//      * @notice Multiplies two values with different decimal scales (e.g., 18 and 6 decimals).
//      * @dev The resulting product of the underlying integers is scaled by (10^N_A * 10^N_B).
//      * To get the target decimal precision (N_target), we must divide by 10^(N_A + N_B - N_target).
//      * Here, we calculate the required division factor (DECIMALS_A_POWER_OF_10 / DECIMALS_B_POWER_OF_10) 
//      * to correct the scaling.
//      * * @param a The first term (e.g., ETH amount, scaled by DECIMALS_A_POWER_OF_10).
//      * @param b The second term (e.g., USDT amount, scaled by DECIMALS_B_POWER_OF_10).
//      * @param decimalsAPowerOf10 The 10^N factor for term A (e.g., WAD for 18 decimals).
//      * @param decimalsBPowerOf10 The 10^N factor for term B (e.g., DECIMALS_6 for 6 decimals).
//      * @param targetDecimalsPowerOf10 The 10^N factor for the desired output precision (e.g., WAD for 18 decimals).
//      * @return The product, scaled by targetDecimalsPowerOf10.
//      */
//     function mulDifferentDecimals(
//         uint256 a,
//         uint256 b,
//         uint256 decimalsAPowerOf10,
//         uint256 decimalsBPowerOf10,
//         uint256 targetDecimalsPowerOf10
//     ) internal pure returns (uint256) {
//         // The combined scaling of a*b is (decimalsAPowerOf10 * decimalsBPowerOf10).
//         // We need to divide this by targetDecimalsPowerOf10.
//         // Division Factor = (decimalsAPowerOf10 * decimalsBPowerOf10) / targetDecimalsPowerOf10
        
//         // This calculation is safer:
//         // (a * b) / (Division Factor)

//         // Correction Factor (how much to divide the product by to get the target scale)
//         // If Target Decimals = N_A, then factor is DECIMALS_B_POWER_OF_10
//         // If Target Decimals = N_B, then factor is DECIMALS_A_POWER_OF_10
        
//         // Let's assume the target scale is the largest scale for simpler code
//         uint256 correctionFactor;
//         if (targetDecimalsPowerOf10 == decimalsAPowerOf10) {
//             correctionFactor = decimalsBPowerOf10;
//         } else if (targetDecimalsPowerOf10 == decimalsBPowerOf10) {
//             correctionFactor = decimalsAPowerOf10;
//         } else {
//             // Handle complex case where target is neither A nor B's decimals
//             // This is complex and usually avoided. We'll simplify for the common case.
//             // (10^(N_A + N_B)) / 10^(N_target)
//             // For simplicity, we stick to the common scenario where target = N_A or N_B
//             // If you need this, the full formula is complicated and risky for overflow.
//             revert("UnsupportedTargetDecimals");
//         }
        
//         return a * b / correctionFactor;
//     }
    
//     /**
//      * @notice Divides two values with different decimal scales (A / B) and returns the result
//      * at the desired target decimal precision (N_target).
//      * @dev The ratio A'/B' is scaled by 10^(N_A - N_B).
//      * To correct the scaling to 10^N_target, we must multiply the ratio by 10^(N_target - (N_A - N_B)).
//      * This is equivalent to pre-scaling the numerator A' by 10^(N_target - N_A) and 
//      * the denominator B' by 10^(0 - N_B).
//      * * The most robust way is to pre-scale the division by the factor 
//      * 10^(N_target) / (10^N_A / 10^N_B) = 10^(N_target - N_A + N_B).
//      * * @param a The numerator (scaled by DECIMALS_A_POWER_OF_10).
//      * @param b The denominator (scaled by DECIMALS_B_POWER_OF_10).
//      * @param decimalsAPowerOf10 The 10^N factor for term A (e.g., WAD for 18 decimals).
//      * @param decimalsBPowerOf10 The 10^N factor for term B (e.g., DECIMALS_6 for 6 decimals).
//      * @param targetDecimalsPowerOf10 The 10^N factor for the desired output precision.
//      * @return The quotient, scaled by targetDecimalsPowerOf10.
//      */
//     function divDifferentDecimals(
//         uint256 a,
//         uint256 b,
//         uint256 decimalsAPowerOf10,
//         uint256 decimalsBPowerOf10,
//         uint256 targetDecimalsPowerOf10
//     ) internal pure returns (uint256) {
//         // Correction Factor = (targetDecimalsPowerOf10 * decimalsBPowerOf10) / decimalsAPowerOf10
//         // We use this factor to pre-scale the numerator 'a' to maintain precision.

//         uint256 correctionFactor = targetDecimalsPowerOf10 * decimalsBPowerOf10 / decimalsAPowerOf10;
        
//         // Result = (a * CorrectionFactor) / b
//         return a * correctionFactor / b;
//     }
// }

// /**
//  * @title FixedPointDemo
//  * @notice Demonstrates the usage of the FixedMath library with ETH (18 decimals) and USDT (6 decimals).
//  */
// contract FixedPointDemo {
//     using FixedMath for uint256;

//     // Standard 18 decimals power of 10
//     uint256 internal constant WAD = FixedMath.WAD;
//     // 6 decimals power of 10
//     uint256 internal constant DECIMALS_6 = FixedMath.DECIMALS_6;
    
//     // --- Sample Amounts ---
//     // Represents 1.23 ETH (18 decimals)
//     uint256 public constant ETH_AMOUNT_18 = 1230000000000000000;
//     // Represents 4000.00 USDT (6 decimals)
//     uint256 public constant USDT_AMOUNT_6 = 4000000000; 

//     // =========================================================================
//     // SAME DECIMALS DEMO (Using 1e18)
//     // =========================================================================
    
//     // ETH_AMOUNT_18 * 2.0 (i.e., WAD * 2)
//     function demoSameDecimalMultiplication() public pure returns (uint256 result_18) {
//         // 1.23 * 2.0 = 2.46 (in 18 decimals)
//         return FixedMath.mul(ETH_AMOUNT_18, 2 * WAD);
//     }

//     // ETH_AMOUNT_18 / 2.0 (i.e., WAD * 2)
//     function demoSameDecimalDivision() public pure returns (uint256 result_18) {
//         // 1.23 / 2.0 = 0.615 (in 18 decimals)
//         return FixedMath.div(ETH_AMOUNT_18, 2 * WAD);
//     }
    
//     // =========================================================================
//     // DIFFERENT DECIMALS DEMO (ETH_18 vs USDT_6)
//     // =========================================================================
    
//     // 4. Multiply 2 numbers with different decimals (ETH_18 * USDT_6)
//     // Target: Result in 18 decimals (the ETH scale)
//     // Expected result: 1.23 * 4000 = 4920.00 (in 18 decimals)
//     function demoDifferentDecimalMultiplication() public pure returns (uint256 result_18) {
//         // Divisor factor needed: 10^(18+6 - 18) = 10^6 (DECIMALS_6)
//         return FixedMath.mulDifferentDecimals(
//             ETH_AMOUNT_18,
//             USDT_AMOUNT_6,
//             WAD,         // 18 decimals power
//             DECIMALS_6,  // 6 decimals power
//             WAD          // Target 18 decimals power
//         ); 
//         // Expected result: 4920 * 1e18
//     }

//     // 5a. Divide 2 numbers with different decimals (ETH_18 / USDT_6)
//     // Numerator has more decimals. Target: Result in 18 decimals (ETH scale)
//     // Expected result: 1.23 / 4000 = 0.0003075 (in 18 decimals)
//     function demoDivEthByUsdt_ReturnEth() public pure returns (uint256 result_18) {
//         // Correction Factor: 10^(18 - 18 + 6) = 10^6 (DECIMALS_6)
//         return FixedMath.divDifferentDecimals(
//             ETH_AMOUNT_18, // Numerator (18 Decimals)
//             USDT_AMOUNT_6, // Denominator (6 Decimals)
//             WAD, 
//             DECIMALS_6, 
//             WAD            // Target 18 decimals power
//         );
//         // Expected result: 307500000000000 (0.0003075 * 1e18)
//     }

//     // 5b. Divide 2 numbers with different decimals (USDT_6 / ETH_18)
//     // Denominator has more decimals. Target: Result in 6 decimals (USDT scale)
//     // Expected result: 4000 / 1.23 = 3252.0325... (in 6 decimals)
//     function demoDivUsdtByEth_ReturnUsdt() public pure returns (uint256 result_6) {
//         // Correction Factor: 10^(6 - 6 + 18) = 10^18 (WAD)
//         return FixedMath.divDifferentDecimals(
//             USDT_AMOUNT_6, // Numerator (6 Decimals)
//             ETH_AMOUNT_18, // Denominator (18 Decimals)
//             DECIMALS_6, 
//             WAD,           // Denominator 18 decimals power
//             DECIMALS_6     // Target 6 decimals power
//         );
//         // Expected result: 3252032520 (3252.032520 * 1e6)
//     }

    // /**
    // * @notice Computes (a * b) / c, maintaining WAD (1e18) precision in the result.
    // * @dev The operation is equivalent to (a * b / c) * WAD.
    // * This is the common pattern for calculating a share or fraction with fixed-point numbers.
    // * @param a The first term (scaled by WAD).
    // * @param b The second term (scaled by WAD).
    // * @param c The divisor (scaled by WAD).
    // * @return The quotient, scaled by WAD.
    // */
    // function mulDiv(
    //     uint256 a, 
    //     uint256 b, 
    //     uint256 c
    // ) internal pure returns (uint256) {
    //     // We want to compute: (a * b) / c * WAD.
    //     // To maintain precision and avoid integer truncation before the final division,
    //     // we must multiply the numerator (a * b) by WAD before dividing by c.
    //     // Result = (a * b) * WAD / c.
        
    //     // NOTE: This simple implementation is prone to a severe overflow if (a * b)
    //     // exceeds the maximum value of a uint256 (2^256 - 1). 
    //     // In production code, one should use a safer, assembly-based mulDiv, 
    //     // or ensure (a * b) / c is the intended WAD-scale operation (which is (a * b) / (c / WAD) 
    //     // but c is also WAD scaled).
        
    //     // Sticking to the simple, but risky, fixed-point logic implied by the existing library:
    //     return a * b * WAD / c; 
    // }
// }
