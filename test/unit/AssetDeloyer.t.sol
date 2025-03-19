// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/HToken.sol";
import "src/Comptroller.sol";
import "src/HErc20.sol";
import "src/utils/AssetDeployer.sol";
import "src/oracles/CompositeOracle.sol";
import "src/HErc20Delegate.sol";

contract AssetDeployerTest is Test {
    Comptroller comptroller;
    Unitroller unitroller_;
    CompositeOracle oracle;

    function setUp() public {}
}
