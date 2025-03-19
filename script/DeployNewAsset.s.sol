// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import "src/Comptroller.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {HToken} from "src/HToken.sol";
import {JumpRateModel} from "src/irm/JumpRateModel.sol";
import {EIP20Interface} from "src/EIP20Interface.sol";
import {MockChainlinkAggregator} from "src/mock/oracle/MockChainlinkAggregator.sol";
import {FaucetToken} from "src/mock/token/FaucetToken.sol";
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";
import {LinkedAssetAggregator} from "src/oracles/LinkedAssetAggregator.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "src/HErc20Delegate.sol";
import "src/utils/AssetDeployer.sol";

contract Deploy is Script {
    address public deployerAddress = vm.envAddress("DEPLOYER");
    address public multisigWallet = vm.envAddress("MUL_SIG_WALLET");
    CompositeOracle oracle = CompositeOracle(address(0));
    Unitroller unitroller = Unitroller(address(0));

    function run() public {
        vm.startBroadcast(deployerAddress);
    }

    function deploy_token() public {}

    function print_log(address underlyingAddr, AssetDeployer assetDeployer) public view {
        (address interestModelAddr, address marketAddr, address priceFeed) = assetDeployer.assets(underlyingAddr);
        HErc20 market = HErc20(marketAddr);
        JumpRateModel interestModel = JumpRateModel(interestModelAddr);

        console.log("market name: ", market.name());
        console.log("market symbol: ", market.symbol());
        console.log("market decimals: ", market.decimals());
        console.log("market initialExchangeRateMantissa: ", market.exchangeRateStored());
        console.log("market address: ", address(market));
        console.log("market priceFeed: ", priceFeed);
        console.log("underlyingAsset ", underlyingAddr);

        console.log("market interestModel address: ", interestModelAddr);
        console.log("market kink: ", interestModel.kink());
        console.log("market baseRatePerTimestamp: ", interestModel.timestampsPerYear());
        console.log("market jumpMultiplierPerTimestamp: ", interestModel.jumpMultiplierPerTimestamp());
    }
}
