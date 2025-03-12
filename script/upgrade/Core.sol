// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FaucetToken} from "src/mock/token/FaucetToken.sol";
import {Configuration} from "./Configuration.sol";
import {MockChainlinkOracle} from "src/mock/oracle/MockChainlinkOracle.sol";
import {FaucetTokenWithPermit} from "src/mock/token/FaucetToken.sol";
import {Comptroller, Unitroller, ComptrollerInterface} from "src/Comptroller.sol";
// import {Rate} from "src/Rate.sol";
import {PriceOracle} from "src/oracles/PriceOracle.sol";
import {ChainlinkPriceFeed} from "src/mock/oracle/ChainlinkPriceFeed.sol";
import {JumpRateModel, InterestRateModel} from "src/irm/JumpRateModel.sol";
import {HErc20Delegate} from "src/upgrades/token/HTokenV2/HErc20Delegate.sol";
import {HErc20Delegator} from "src/HErc20Delegator.sol";
import {HErc20} from "src/upgrades/token/HTokenV2/HErc20.sol";
import {HToken} from "src/HToken.sol";
import {WHSK} from "src/mock/token/WHSK.sol";
// Oracle contracts
import {CompositeOracle} from "src/oracles/CompositeOracle.sol";
import {MultiRewardDistributor} from "src/rewards/MultiRewardDistributor.sol";
import {IMultiRewardDistributor} from "src/rewards/IMultiRewardDistributor.sol";
import {MockSequencer} from "src/mock/oracle/MockSequencer.sol";
import {MockChainlinkAggregator} from "src/mock/oracle/MockChainlinkAggregator.sol";
import {AssetDeployer} from "src/utils/AssetDeployer.sol";

contract CoreScript is Test, Script, Configuration {
    using Strings for uint256;
    using stdJson for string;

    uint256 public constant ASSET_INITIAL_DEPOSIT = 1000;

    function deployCore(address _admin, address _multisigWallet) public {
        Unitroller unitroller = new Unitroller();
        Comptroller comptroller = new Comptroller();
        MockSequencer mockSequencer = new MockSequencer();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        unitroller._setPendingAdmin(_admin);
        Comptroller comptrollerProxy = Comptroller(address(unitroller));
        comptrollerProxy._setPauseGuardian(_admin);
        comptrollerProxy._setBorrowCapGuardian(_admin);
        comptrollerProxy._setSupplyCapGuardian(_admin);
        comptrollerProxy._setCloseFactor(closeFactorMantissa);
        comptrollerProxy._setLiquidationIncentive(liquidationIncentiveMantissa);

        // ---------------------------
        // RewardDistributor deployment start
        // ---------------------------
        ProxyAdmin rewardDistributorProxyAdmin = new ProxyAdmin(_admin);
        MultiRewardDistributor rewardDistributorImpl = new MultiRewardDistributor();
        TransparentUpgradeableProxy rewardDistributor = new TransparentUpgradeableProxy(
            address(rewardDistributorImpl),
            address(rewardDistributorProxyAdmin),
            abi.encodeWithSignature("initialize(address,address)", address(unitroller), _admin)
        );
        MultiRewardDistributor rewardDistributorProxy = MultiRewardDistributor(payable(address(rewardDistributor)));
        rewardDistributorProxyAdmin.transferOwnership(_admin);
        // ---------------------------
        // RewardDistributor deployment end
        // ---------------------------

        // ---------------------------
        // PriceFeed deployment start
        // ---------------------------
        ProxyAdmin priceFeedProxyAdmin = new ProxyAdmin(_admin);
        CompositeOracle priceFeedImpl = new CompositeOracle();
        TransparentUpgradeableProxy priceFeedProxy = new TransparentUpgradeableProxy(
            address(priceFeedImpl), address(priceFeedProxyAdmin), abi.encodeWithSignature("initialize()", "")
        );
        CompositeOracle priceFeed = CompositeOracle(address(priceFeedProxy));
        priceFeed.setFreshCheck(86400);
        priceFeed.setGracePeriodTime(3600);
        priceFeed.setSequencerUptimeFeed(address(mockSequencer));

        // priceFeed.setPyth(0xA2aa501b19aff244D90cc15a4Cf739D2725B5729);

        // TODO - priceFeedProxy.setFallbackOracle
        // ---------------------------
        // PriceFeed deployment end
        // ---------------------------

        HErc20Delegate tErc20Delegate = new HErc20Delegate();
        comptrollerProxy._setRewardDistributor(IMultiRewardDistributor(address(rewardDistributorProxy)));
        comptrollerProxy._setPriceOracle(PriceOracle(address(priceFeed)));

        comptrollerProxy._setRewardDistributor(IMultiRewardDistributor(address(rewardDistributorProxy)));
        comptrollerProxy._setPriceOracle(PriceOracle(address(priceFeed)));

        AssetDeployer assetDeployer = new AssetDeployer(
            _admin,
            _multisigWallet,
            address(tErc20Delegate),
            address(comptrollerProxy),
            address(comptrollerProxy),
            address(priceFeed)
        );

        addAddress("RTOKEN_IMPLEMENTATION", address(tErc20Delegate), block.chainid, true);
        // addAddress("REWARD_TOKEN", address(rateToken), block.chainid, true);
        addAddress("UNITROLLER", address(unitroller), block.chainid, true);
        addAddress("COMPTROLLER", address(comptroller), block.chainid, true);
        addAddress("MRD_PROXY", address(rewardDistributor), block.chainid, true);
        addAddress("MRD_IMPL", address(rewardDistributorImpl), block.chainid, true);
        addAddress("MRD_PROXY_ADMIN", address(rewardDistributorProxyAdmin), block.chainid, true);
        addAddress("PRICE_FEED_ORACLE", address(priceFeed), block.chainid, true);
        addAddress("ASSET_DEPLOYER", address(assetDeployer), block.chainid, true);
    }

    /// @notice no contracts are deployed in this proposal
    function deployAsset(address _deployer) public {
        Configuration.RTokenConfiguration[] memory hTokenConfigs = getRTokenConfigurations(block.chainid);
        AssetDeployer assetDeployer = AssetDeployer(getAddress("ASSET_DEPLOYER"));
        CompositeOracle priceFeed = CompositeOracle(getAddress("PRICE_FEED_ORACLE"));
        Unitroller unitroller = Unitroller(getAddress("UNITROLLER"));
        uint256 hTokenConfigsLength = hTokenConfigs.length;

        priceFeed.transferOwnership(address(assetDeployer));
        unitroller._setPendingAdmin(address(assetDeployer));

        //// create all of the hTokens according to the configuration in Config.sol
        for (uint256 i = 0; i < hTokenConfigsLength; i++) {
            Configuration.RTokenConfiguration memory config = hTokenConfigs[i];
            ERC20 currentToken;

            if (keccak256(abi.encodePacked(config.tokenAddressName)) == keccak256(abi.encodePacked("WHSK"))) {
                WHSK whsk = new WHSK();
                whsk.deposit{value: ASSET_INITIAL_DEPOSIT}();
                currentToken = ERC20(address(whsk));
            } else {
                FaucetToken faucetToken = new FaucetToken(
                    10000000000 * 10 ** config.decimal, config.name, uint8(config.decimal), config.tokenAddressName
                );
                currentToken = ERC20(address(faucetToken));
                faucetToken.allocateTo(_deployer, 10000000000 * 10 ** config.decimal);
            }

            currentToken.approve(address(assetDeployer), ASSET_INITIAL_DEPOSIT);

            address currentMarket = assetDeployer.deployAsset(
                address(currentToken),
                config.name,
                config.symbol,
                currentToken.decimals(),
                initialExchangeRate,
                config.collateralFactor,
                config.reserveFactor,
                config.seizeShare,
                config.supplyCap,
                config.borrowCap,
                config.chainlinkPriceFeed,
                config.jrm.baseRatePerYear,
                config.jrm.multiplierPerYear,
                config.jrm.jumpMultiplierPerYear,
                config.jrm.kink,
                ASSET_INITIAL_DEPOSIT
            );

            (address interestModel,,) = assetDeployer.assets(address(currentToken));

            addAddress(config.tokenAddressName, address(currentToken), block.chainid, true);
            addAddress(config.symbol, currentMarket, block.chainid, true);
            addAddress(
                string(abi.encodePacked("JUMP_RATE_IRM_", config.addressesString)),
                address(interestModel),
                block.chainid,
                true
            );
        }

        assetDeployer.transferOwnership();
        unitroller._acceptAdmin();
    }

    function deployAssetWithoutHelper(address deployer) public {
        Configuration.RTokenConfiguration[] memory hTokenConfigs = getRTokenConfigurations(block.chainid);
        address priceFeedAddr = getAddress("PRICE_FEED_ORACLE");
        Comptroller competroller = Comptroller(getAddress("UNITROLLER"));
        CompositeOracle priceFeedOracle = CompositeOracle(priceFeedAddr);
        uint256 hTokenConfigsLength = hTokenConfigs.length;

        //// create all of the hTokens according to the configuration in Config.sol
        unchecked {
            for (uint256 i = 0; i < hTokenConfigsLength; i++) {
                Configuration.RTokenConfiguration memory config = hTokenConfigs[i];
                ERC20 currentToken;

                if (keccak256(abi.encodePacked(config.tokenAddressName)) == keccak256(abi.encodePacked("WHSK"))) {
                    WHSK whsk = new WHSK();
                    whsk.deposit{value: ASSET_INITIAL_DEPOSIT}();
                    currentToken = ERC20(address(whsk));
                } else {
                    FaucetToken faucetToken = new FaucetToken(
                        10000000000 * 10 ** config.decimal, config.name, uint8(config.decimal), config.tokenAddressName
                    );
                    currentToken = ERC20(address(faucetToken));
                    faucetToken.allocateTo(deployer, 10000000000 * 10 ** config.decimal);
                }

                (JumpRateModel rateModel, HErc20Delegator market) = createErc20Market(
                    currentToken,
                    initialExchangeRate,
                    config.jrm.baseRatePerYear,
                    config.jrm.multiplierPerYear,
                    config.jrm.jumpMultiplierPerYear,
                    config.jrm.kink,
                    config.name,
                    config.symbol,
                    deployer
                );

                HToken hToken = HToken(address(market));
                priceFeedOracle.setHTokenConfig(hToken, address(currentToken), uint8(config.decimal));

                address[] memory aggregators_ = new address[](1);
                aggregators_[0] = config.chainlinkPriceFeed;

                priceFeedOracle.setOracle(HToken(address(market)), aggregators_);
                priceFeedOracle.setOracle(HToken(config.tokenAddress), aggregators_);

                competroller._supportMarket(hToken);

                // competroller._setBorrowPaused(hToken, true);
                // competroller._setMintPaused(hToken, true);
                // competroller._setUserMintPaused(address(hToken), true);

                addAddress(config.tokenAddressName, address(currentToken), block.chainid, true);
                addAddress(config.symbol, address(market), block.chainid, true);
                addAddress(
                    string(abi.encodePacked("JUMP_RATE_IRM_", config.addressesString)),
                    address(rateModel),
                    block.chainid,
                    true
                );
            }
        }
    }

    function createErc20Market(
        ERC20 underlyingAsset,
        uint256 _initialExchangeRateMantissa,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        string memory _name,
        string memory _symbol,
        address deployer
    ) public returns (JumpRateModel rateModel, HErc20Delegator market) {
        Comptroller comptrollerProxy = Comptroller(getAddress("UNITROLLER"));

        rateModel = new JumpRateModel(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink);

        market = new HErc20Delegator(
            address(underlyingAsset),
            ComptrollerInterface(comptrollerProxy),
            rateModel,
            _initialExchangeRateMantissa,
            _name,
            _symbol,
            underlyingAsset.decimals(),
            payable(deployer),
            getAddress("RTOKEN_IMPLEMENTATION"),
            ""
        );
    }

    function transferOwnership(address wallet) public {
        Unitroller unitroller = Unitroller(getAddress("UNITROLLER"));
        Ownable priceFeedOracle = Ownable(getAddress("PRICE_FEED_ORACLE"));

        unitroller._setPendingAdmin(wallet);
        priceFeedOracle.transferOwnership(wallet);
    }

    /// helper function to validate supply and borrow caps
    function _validateCaps(Configuration.RTokenConfiguration memory config) private view {
        {
            if (config.supplyCap != 0 || config.borrowCap != 0) {
                uint8 decimals = ERC20(getAddress(config.tokenAddressName)).decimals();

                ///  defaults to false, dev can set to true to  these checks

                if (config.supplyCap != 0 && !vm.envOr("OVERRIDE_SUPPLY_CAP", false)) {
                    /// strip off all the decimals
                    uint256 adjustedSupplyCap = config.supplyCap / (10 ** decimals);
                    require(
                        // TODO - cap need to be ocnfirm
                        adjustedSupplyCap < 100000000 ether,
                        "supply cap suspiciously high, if this is the right supply cap, set OVERRIDE_SUPPLY_CAP environment variable to true"
                    );
                }

                if (config.borrowCap != 0 && !vm.envOr("OVERRIDE_BORROW_CAP", false)) {
                    uint256 adjustedBorrowCap = config.borrowCap / (10 ** decimals);
                    require(
                        // TODO - cap need to be ocnfirm
                        adjustedBorrowCap < 100000000 ether,
                        "borrow cap suspiciously high, if this is the right borrow cap, set OVERRIDE_BORROW_CAP environment variable to true"
                    );
                }
            }
        }
    }

    // TODO - Need to refine script
    function validate(address deployer) public {
        Configuration.RTokenConfiguration[] memory hTokenConfigs = getRTokenConfigurations(block.chainid);
        Comptroller comptroller = Comptroller(getAddress("UNITROLLER"));

        unchecked {
            for (uint256 i = 0; i < hTokenConfigs.length; i++) {
                Configuration.RTokenConfiguration memory config = hTokenConfigs[i];

                uint256 borrowCap = comptroller.borrowCaps(getAddress(config.symbol));
                uint256 supplyCap = comptroller.supplyCaps(getAddress(config.symbol));

                uint256 maxBorrowCap = (supplyCap * 10) / 9;

                /// validate borrow cap is always lte 90% of supply cap
                assertTrue(borrowCap <= maxBorrowCap, "borrow cap exceeds max borrow");

                /// hToken Assertions
                assertFalse(comptroller.mintGuardianPaused(getAddress(config.symbol)));
                /// minting allowed by guardian
                assertFalse(comptroller.borrowGuardianPaused(getAddress(config.symbol)));
                /// borrowing allowed by guardian
                assertEq(borrowCap, config.borrowCap);
                assertEq(supplyCap, config.supplyCap);

                /// assert hToken irModel is correct
                JumpRateModel jrm = JumpRateModel(getAddress(string(abi.encodePacked("JUMP_RATE_IRM_", config.symbol))));
                assertEq(address(HToken(getAddress(config.symbol)).interestRateModel()), address(jrm));

                HErc20 hToken = HErc20(getAddress(config.symbol));

                /// reserve factor and protocol seize share
                assertEq(hToken.protocolSeizeShareMantissa(), config.seizeShare);
                assertEq(hToken.reserveFactorMantissa(), config.reserveFactor);

                /// assert initial hToken balances are correct
                assertTrue(hToken.balanceOf(address(deployer)) > 0);
                /// deployer has some
                assertEq(hToken.balanceOf(address(0)), 1);
                /// address 0 has 1 wei of assets

                /// assert hToken admin is the temporal deployer
                assertEq(address(hToken.admin()), address(deployer));

                /// assert hToken comptroller is correct
                assertEq(address(hToken.comptroller()), getAddress("UNITROLLER"));

                /// assert hToken underlying is correct
                assertEq(address(hToken.underlying()), getAddress(config.tokenAddressName));

                /// assert hToken delegate is uniform across contracts
                assertEq(
                    address(HErc20Delegator(payable(address(hToken))).implementation()),
                    getAddress("RTOKEN_IMPLEMENTATION")
                );

                /// assert hToken initial exchange rate is correct
                assertEq(hToken.exchangeRateCurrent(), initialExchangeRate);

                /// assert hToken name and symbol are correct
                assertEq(hToken.name(), config.name);
                assertEq(hToken.symbol(), config.symbol);
                assertEq(hToken.decimals(), config.decimal);
            }
        }
    }
}
