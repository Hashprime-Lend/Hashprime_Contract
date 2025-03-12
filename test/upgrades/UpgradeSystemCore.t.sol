// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
// import "src/rewards/MultiRewardDistributor.sol";
import {IMultiRewardDistributor as IMultiRewardDistributorV1} from "src/rewards/IMultiRewardDistributor.sol";
import {MultiRewardDistributor} from "src/upgrades/rewards/MultiRewardDistributor.sol";
import {IMultiRewardDistributor} from "src/upgrades/rewards/IMultiRewardDistributor.sol";
import {HToken} from "src/upgrades/token/HTokenV2/HToken.sol";
import {HToken as HTokenV1} from "src/HToken.sol";
import {FaucetToken, FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {Comptroller} from "src/Comptroller.sol";
import {HErc20Immutable} from "src/mock/upgrades/HErc20Immutable.sol";
import {InterestRateModel} from "src/irm/InterestRateModel.sol";
import {SimplePriceOracle} from "src/mock/oracle/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "src/irm/WhitePaperInterestRateModel.sol";

contract UpgradeSystemCoreTest is Test {
    address public deployerAddress = vm.envAddress("DEPLOYER");

    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetTokenWithPermit token;
    FaucetTokenWithPermit emissionToken;
    HErc20Immutable hToken;
    InterestRateModel irModel;

    event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);

    function setUp() public {
        vm.startPrank(deployerAddress);

        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        token = new FaucetTokenWithPermit(100000 ether, "Testing", 18, "TEST");

        irModel = new WhitePaperInterestRateModel(0.1e18, 0.45e18);

        hToken = new HErc20Immutable(
            address(token),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test hToken",
            "hTEST",
            18,
            payable(deployerAddress)
        );

        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(HTokenV1(address(hToken)));
        oracle.setUnderlyingPrice(HTokenV1(address(hToken)), 1e18);

        comptroller._setCollateralFactor(HTokenV1(address(hToken)), 0.7e18); // 50% CF

        emissionToken = new FaucetTokenWithPermit(0, "Emission Token", 18, "EMIT");
    }

    function testBorrowRTokenSucceedsWithFee() public {
        vm.warp(vm.getBlockTimestamp() + 1000);
        vm.roll(vm.getBlockNumber() + 333);

        uint256 mintAmount = 1e18;
        uint256 borrowFeePercentage = 0.001e18;

        vm.startPrank(deployerAddress);

        hToken._setBorrowFee(borrowFeePercentage);

        vm.warp(vm.getBlockTimestamp() + 1000 + 3);
        vm.roll(vm.getBlockNumber() + 333 + 1);

        // uint256 startingTokenBalance = token.balanceOf(address(hToken));
        deal(address(token), deployerAddress, mintAmount);
        token.approve(address(hToken), mintAmount);

        uint256 mintErr = hToken.mint(mintAmount);
        assertEq(mintErr, 0);
        /// ensure successful mint

        assertTrue(hToken.balanceOf(deployerAddress) > 0);

        address[] memory hTokens = new address[](1);
        hTokens[0] = address(hToken);

        (bool isListed,) = comptroller.markets(address(hToken));

        comptroller.enterMarkets(hTokens);

        assertTrue(isListed);
        assertTrue(comptroller.checkMembership(deployerAddress, HTokenV1(address(hToken))));

        uint256 borrowAmount = 0.5e18;
        uint256 borrowFeeReserve = borrowAmount * borrowFeePercentage / 1e18;

        uint256 balance = token.balanceOf(deployerAddress);

        // vm.expectEmit(false, false, false, true, address(hToken));
        // emit ReservesAdded(deployerAddress, 0, 0);
        uint256 borrowErr = hToken.borrow(borrowAmount);

        assertEq(borrowErr, 0);

        uint256 balanceOfAfterBorrow = token.balanceOf(deployerAddress);

        assertApproxEqRel(balanceOfAfterBorrow - balance, borrowAmount - borrowFeeReserve, 0.001e18);
    }
}
