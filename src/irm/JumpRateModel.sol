// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "./InterestRateModel.sol";

/**
 * @title JumpRateModel Contract
 */
contract JumpRateModel is InterestRateModel {
    event NewInterestParams(
        uint256 baseRatePerTimestamp, uint256 multiplierPerTimestamp, uint256 jumpMultiplierPerTimestamp, uint256 kink
    );

    /**
     * @notice The approximate number of timestamps per year that is assumed by the interest rate model
     */
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint256 public multiplierPerTimestamp;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint256 public baseRatePerTimestamp;

    /**
     * @notice The multiplierPerTimestamp after hitting a specified utilization point
     */
    uint256 public jumpMultiplierPerTimestamp;

    /**
     * @notice The utilization point at which the jump multiplier is applied
     */
    uint256 public kink;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerTimestamp after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    constructor(uint256 baseRatePerYear, uint256 multiplierPerYear, uint256 jumpMultiplierPerYear, uint256 kink_) {
        baseRatePerTimestamp = baseRatePerYear * 1e18 / timestampsPerYear / 1e18;
        multiplierPerTimestamp = multiplierPerYear * 1e18 / timestampsPerYear / 1e18;
        jumpMultiplierPerTimestamp = jumpMultiplierPerYear * 1e18 / timestampsPerYear / 1e18;
        kink = kink_;

        emit NewInterestParams(baseRatePerTimestamp, multiplierPerTimestamp, jumpMultiplierPerTimestamp, kink);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        if (borrows == 0) {
            return 0;
        }
        return (borrows * 1e18) / (cash + borrows - reserves);
    }

    /**
     * @notice Calculates the current borrow rate per timestamp, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per timestamp as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view override returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            return (util * multiplierPerTimestamp) / 1e18 + baseRatePerTimestamp;
        } else {
            uint256 normalRate = (kink * multiplierPerTimestamp) / 1e18 + baseRatePerTimestamp;
            uint256 excessUtil = util - kink;
            return (excessUtil * jumpMultiplierPerTimestamp) / 1e18 + normalRate;
        }
    }

    /**
     * @notice Calculates the current supply rate per timestamp
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per timestamp as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa)
        public
        view
        override
        returns (uint256)
    {
        uint256 oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / 1e18;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / 1e18;
    }
}
