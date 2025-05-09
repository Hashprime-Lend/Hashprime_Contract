// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/Comptroller.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {HToken} from "src/HToken.sol";
import {JumpRateModel} from "src/irm/JumpRateModel.sol";
import {EIP20Interface} from "src/EIP20Interface.sol";
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AssetDeployer is Ownable {
    using SafeERC20 for IERC20;

    error DeployAssetBalanceNotEnough(address asset, uint256 balance);
    error DeployAssetAllowanceNotEnough(address asset, uint256 allowance);

    address public deployerAddress;
    address public multisigWallet;
    address public RTOKEN_IMPLEMENTATION;
    CompositeOracle public oracle;
    Comptroller public comptrollerProxy;
    Unitroller public unitroller;

    struct Market {
        address interestModel;
        address market;
        address priceFeed;
    }

    mapping(address => Market) public assets;

    constructor(
        address _deployerAddress,
        address _multisigWallet,
        address _HTOKEN_IMPLEMENTATION,
        address _comptrollerProxy,
        address _unitroller,
        address _oracle
    ) Ownable(_deployerAddress) {
        deployerAddress = _deployerAddress;
        multisigWallet = _multisigWallet;
        RTOKEN_IMPLEMENTATION = _HTOKEN_IMPLEMENTATION;
        comptrollerProxy = Comptroller(_comptrollerProxy);
        unitroller = Unitroller(_unitroller);
        oracle = CompositeOracle(_oracle);
    }

    function deployAsset(
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialExchangeRateMantissa,
        uint256 collateralFactor,
        uint256 reserveFactor,
        uint256 seizeShare,
        uint256 supplyCap,
        uint256 borrowCap,
        address chainlinkAggregator,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        uint256 initialMintAmount
    ) public returns (address) {
        // Use SafeERC20 for secure token transfers
        IERC20 token = IERC20(underlyingAsset);
        uint256 assetAllowance = token.allowance(msg.sender, address(this));

        if (assetAllowance < initialMintAmount) {
            revert DeployAssetAllowanceNotEnough(underlyingAsset, assetAllowance);
        }

        if (unitroller.admin() != address(this)) {
            unitroller._acceptAdmin();
        }

        token.safeTransferFrom(msg.sender, address(this), initialMintAmount);

        JumpRateModel interestRateModel =
            new JumpRateModel(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink);

        HErc20Delegator newMarket = new HErc20Delegator(
            underlyingAsset,
            ComptrollerInterface(address(comptrollerProxy)),
            interestRateModel,
            initialExchangeRateMantissa,
            name,
            symbol,
            decimals,
            payable(deployerAddress),
            RTOKEN_IMPLEMENTATION,
            ""
        );

        HToken hToken = HToken(address(newMarket));

        EIP20Interface underlyingERC20 = EIP20Interface(underlyingAsset);

        // Configure Oracle
        oracle.setHTokenConfig(hToken, address(underlyingAsset), decimals);

        address[] memory aggregators_ = new address[](1);
        aggregators_[0] = chainlinkAggregator;

        oracle.setOracle(hToken, aggregators_);

        comptrollerProxy._supportMarket(hToken);

        HToken[] memory hTokens = new HToken[](1);
        uint256[] memory supplyCaps = new uint256[](1);
        uint256[] memory borrowCaps = new uint256[](1);
        hTokens[0] = hToken;
        supplyCaps[0] = supplyCap;
        borrowCaps[0] = borrowCap;

        hToken._setReserveFactor(reserveFactor);
        hToken._setProtocolSeizeShare(seizeShare);
        comptrollerProxy._setCollateralFactor(hToken, collateralFactor);
        comptrollerProxy._setMarketSupplyCaps(hTokens, supplyCaps);
        comptrollerProxy._setMarketBorrowCaps(hTokens, borrowCaps);

        underlyingERC20.approve(address(hToken), 1);
        HErc20Delegator(payable(address(hToken))).mint(1);
        hToken.approve(address(0), 1);
        hToken.transfer(address(0), 1);

        comptrollerProxy._setBorrowPaused(hToken, true);
        comptrollerProxy._setMintPaused(hToken, true);

        assets[underlyingAsset] = Market({
            interestModel: address(interestRateModel),
            market: address(newMarket),
            priceFeed: chainlinkAggregator
        });

        return address(newMarket);
    }

    function transferOwnership() public {
        unitroller._setPendingAdmin(payable(multisigWallet));
        oracle.transferOwnership(multisigWallet);
    }
}
