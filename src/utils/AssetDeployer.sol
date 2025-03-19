// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/Comptroller.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
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
    error MintCapMustGreaterThanInitialMintAmount();
    error UnitrollerPendingAdminNotSetup();

    struct Market {
        address interestModel;
        address market;
        address priceFeed;
    }

    address public deployerAddress;
    address public multisigWallet;
    CompositeOracle public oracle;
    Unitroller public unitroller;

    mapping(address => Market) public assets;

    // Event definitions
    event AssetSetup(
        address indexed underlyingAsset,
        address indexed market,
        uint8 decimals,
        uint256 collateralFactor,
        uint256 reserveFactor,
        uint256 seizeShare,
        uint256 supplyCap,
        uint256 borrowCap,
        uint256 initialMintAmount,
        address aggregator,
        bool paused
    );

    constructor(address _deployerAddress, address _multisigWallet, address _unitroller, address _oracle)
        Ownable(_deployerAddress)
    {
        deployerAddress = _deployerAddress;
        multisigWallet = _multisigWallet;
        unitroller = Unitroller(_unitroller);
        oracle = CompositeOracle(_oracle);
    }

    function deployAsset(
        address underlyingAsset,
        address implementation,
        address[] memory aggregators,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialExchangeRateMantissa,
        uint256 collateralFactor,
        uint256 reserveFactor,
        uint256 seizeShare,
        uint256 supplyCap,
        uint256 borrowCap,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        uint256 initialMintAmount,
        bool pause
    ) public returns (address) {
        IERC20 token = IERC20(underlyingAsset);
        uint256 assetAllowance = token.allowance(msg.sender, address(this));
        uint256 assetBalance = token.allowance(msg.sender, address(this));

        if (unitroller.pendingAdmin() != address(this)) {
            revert UnitrollerPendingAdminNotSetup();
        }

        if (assetAllowance < initialMintAmount) {
            revert DeployAssetAllowanceNotEnough(underlyingAsset, assetAllowance);
        }

        if (assetBalance < initialMintAmount) {
            revert DeployAssetBalanceNotEnough(underlyingAsset, assetBalance);
        }

        if (supplyCap < initialMintAmount) {
            revert MintCapMustGreaterThanInitialMintAmount();
        }

        unitroller._acceptAdmin();
        token.safeTransferFrom(msg.sender, address(this), initialMintAmount);

        Comptroller comptrollerProxy = Comptroller(address(unitroller));
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
            payable(address(this)),
            implementation,
            ""
        );

        HToken hToken = HToken(address(newMarket));

        // Configure Oracle
        oracle.setHTokenConfig(hToken, address(underlyingAsset), decimals);
        oracle.setOracle(hToken, aggregators);
        oracle.setOracle(HToken(underlyingAsset), aggregators);

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

        token.forceApprove(address(hToken), initialMintAmount);
        HErc20Delegator(payable(address(hToken))).mint(initialMintAmount);
        hToken.approve(address(0), initialMintAmount);
        hToken.transfer(address(0), initialMintAmount);

        assets[underlyingAsset] =
            Market({interestModel: address(interestRateModel), market: address(newMarket), priceFeed: aggregators[0]});

        if (pause) {
            comptrollerProxy._setBorrowPaused(hToken, true);
            comptrollerProxy._setMintPaused(hToken, true);
        }

        hToken._setPendingAdmin(payable(multisigWallet));

        emit AssetSetup(
            underlyingAsset,
            address(newMarket),
            decimals,
            collateralFactor,
            reserveFactor,
            seizeShare,
            supplyCap,
            borrowCap,
            initialMintAmount,
            aggregators[0],
            pause
        );

        return address(newMarket);
    }

    function transferOwnership() public {
        unitroller._setPendingAdmin(payable(multisigWallet));
        oracle.transferOwnership(multisigWallet);
    }
}
