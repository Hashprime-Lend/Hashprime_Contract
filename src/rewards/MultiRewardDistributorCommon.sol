// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "../HToken.sol";

// The commonly structures and events for the MultiRewardDistributor
interface MultiRewardDistributorCommon {
    struct MarketConfig {
        // The owner/admin of the emission config
        address owner;
        // The emission token
        address emissionToken;
        // Scheduled to end at this time
        uint256 endTime;
        // Supplier global state
        uint224 supplyGlobalIndex;
        uint32 supplyGlobalTimestamp;
        // Borrower global state
        uint224 borrowGlobalIndex;
        uint32 borrowGlobalTimestamp;
        uint256 supplyEmissionsPerSec;
        uint256 borrowEmissionsPerSec;
    }

    struct MarketEmissionConfig {
        MarketConfig config;
        mapping(address => uint256) supplierIndices;
        mapping(address => uint256) supplierRewardsAccrued;
        mapping(address => uint256) borrowerIndices;
        mapping(address => uint256) borrowerRewardsAccrued;
    }

    struct RewardInfo {
        address emissionToken;
        uint256 totalAmount;
        uint256 supplySide;
        uint256 borrowSide;
    }

    struct IndexUpdate {
        uint224 newIndex;
        uint32 newTimestamp;
    }

    struct HTokenData {
        uint256 hTokenBalance;
        uint256 borrowBalanceStored;
    }

    struct RewardWithHToken {
        address hToken;
        RewardInfo[] rewards;
    }

    // Global index updates
    event GlobalSupplyIndexUpdated(
        HToken hToken, address emissionToken, uint256 newSupplyIndex, uint32 newSupplyGlobalTimestamp
    );
    event GlobalBorrowIndexUpdated(HToken hToken, address emissionToken, uint256 newIndex, uint32 newTimestamp);

    // Reward Disbursal
    event DisbursedSupplierRewards(
        HToken indexed hToken, address indexed supplier, address indexed emissionToken, uint256 totalAccrued
    );
    event DisbursedBorrowerRewards(
        HToken indexed hToken, address indexed borrower, address indexed emissionToken, uint256 totalAccrued
    );

    // Admin update events
    event NewConfigCreated(
        HToken indexed hToken,
        address indexed owner,
        address indexed emissionToken,
        uint256 supplySpeed,
        uint256 borrowSpeed,
        uint256 endTime
    );
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);
    event NewEmissionCap(uint256 oldEmissionCap, uint256 newEmissionCap);
    event NewEmissionConfigOwner(
        HToken indexed hToken, address indexed emissionToken, address currentOwner, address newOwner
    );
    event NewRewardEndTime(
        HToken indexed hToken, address indexed emissionToken, uint256 currentEndTime, uint256 newEndTime
    );
    event NewSupplyRewardSpeed(
        HToken indexed hToken, address indexed emissionToken, uint256 oldRewardSpeed, uint256 newRewardSpeed
    );
    event NewBorrowRewardSpeed(
        HToken indexed hToken, address indexed emissionToken, uint256 oldRewardSpeed, uint256 newRewardSpeed
    );
    event FundsRescued(address token, uint256 amount);

    // Pause guardian stuff
    event RewardsPaused();
    event RewardsUnpaused();

    // Errors
    event InsufficientTokensToEmit(address payable user, address rewardToken, uint256 amount);
}
