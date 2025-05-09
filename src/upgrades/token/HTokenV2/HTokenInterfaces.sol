// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "./ErrorReporter.sol";
import "src/ComptrollerInterface.sol";
import "src/irm/InterestRateModel.sol";
import "src/EIP20NonStandardInterface.sol";

contract HTokenStorage {
    /// @dev Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice EIP-20 token name for this token
    string public name;

    /// @notice EIP-20 token symbol for this token
    string public symbol;

    /// @notice EIP-20 token decimals for this token
    uint8 public decimals;

    /// @notice Maximum borrow rate that can ever be applied (.0005% / block)
    uint256 internal constant borrowRateMaxMantissa = 0.0005e16;

    // @notice Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant reserveFactorMaxMantissa = 1e18;

    /// @notice Administrator for this contract
    address payable public admin;

    /// @notice Pending administrator for this contract
    address payable public pendingAdmin;

    /// @notice Contract which oversees inter-hToken operations
    ComptrollerInterface public comptroller;

    /// @notice Model which tells what the current interest rate should be
    InterestRateModel public interestRateModel;

    // @notice Initial exchange rate used when minting the first RTokens (used when totalSupply = 0)
    uint256 internal initialExchangeRateMantissa;

    /// @notice Fraction of interest currently set aside for reserves
    uint256 public reserveFactorMantissa;

    /// @notice Block timestamp that interest was last accrued at
    uint256 public accrualBlockTimestamp;

    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint256 public borrowIndex;

    /// @notice Total amount of outstanding borrows of the underlying in this market
    uint256 public totalBorrows;

    /// @notice Total amount of reserves of the underlying held in this market
    uint256 public totalReserves;

    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    /// @notice Official record of token balances for each account
    mapping(address => uint256) internal accountTokens;

    /// @notice Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint256)) internal transferAllowances;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    // @notice Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /// @notice Share of seized collateral that is added to reserves
    uint256 public protocolSeizeShareMantissa;
}

abstract contract HTokenInterface is HTokenStorage {
    /// @notice Indicator that this is a HToken contract (for inspection)
    bool public constant isHToken = true;

    /**
     * Market Events **
     */

    /// @notice Event emitted when interest is accrued
    event AccrueInterest(uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);

    /// @notice Event emitted when tokens are minted
    event Mint(address minter, uint256 mintAmount, uint256 mintTokens);

    /// @notice Event emitted when tokens are redeemed
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /// @notice Event emitted when underlying is borrowed
    event Borrow(address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);

    /// @notice Event emitted when a borrow is repaid
    event RepayBorrow(
        address payer, address borrower, uint256 repayAmount, uint256 accountBorrows, uint256 totalBorrows
    );

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrow(
        address liquidator, address borrower, uint256 repayAmount, address hTokenCollateral, uint256 seizeTokens
    );

    /**
     * Admin Events **
     */

    /// @notice Event emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Event emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice Event emitted when comptroller is changed
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /// @notice Event emitted when interestRateModel is changed
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /// @notice Event emitted when the reserve factor is changed
    event NewReserveFactor(uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa);

    /// @notice Event emitted when the redemption reserve factor is changed
    event NewRedemptionReserveFactor(uint256 oldRedemptionReserveFactor, uint256 newRedemptionReserveFactor);

    /// @notice Event emitted when the protocol seize share is changed
    event NewProtocolSeizeShare(uint256 oldProtocolSeizeShareMantissa, uint256 newProtocolSeizeShareMantissa);

    /// @notice Event emitted when the reserves are added
    event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);

    /// @notice Event emitted when the reserves are reduced
    event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);

    /// @notice EIP20 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice EIP20 Approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice New borrow fee setup event
    event NewBorrowFee(uint256 oldBorrowFeeMantissa, uint256 newBorrowFeeMantissa);

    /**
     * User Interface **
     */
    function isEthDerivative() external view virtual returns (bool);
    function transfer(address dst, uint256 amount) external virtual returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external virtual returns (bool);
    function approve(address spender, uint256 amount) external virtual returns (bool);
    function allowance(address owner, address spender) external view virtual returns (uint256);
    function balanceOf(address owner) external view virtual returns (uint256);
    function balanceOfUnderlying(address owner) external virtual returns (uint256);
    function getAccountSnapshot(address account) external view virtual returns (uint256, uint256, uint256, uint256);
    function borrowRatePerBlock() external view virtual returns (uint256);
    function supplyRatePerBlock() external view virtual returns (uint256);
    function totalBorrowsCurrent() external virtual returns (uint256);
    function borrowBalanceCurrent(address account) external virtual returns (uint256);
    function borrowBalanceStored(address account) external view virtual returns (uint256);
    function exchangeRateCurrent() external virtual returns (uint256);
    function exchangeRateStored() external view virtual returns (uint256);
    function getCash() external view virtual returns (uint256);
    function accrueInterest() external virtual returns (uint256);
    function seize(address liquidator, address borrower, uint256 seizeTokens) external virtual returns (uint256);

    /**
     * Admin Functions **
     */
    function _setPendingAdmin(address payable newPendingAdmin) external virtual returns (uint256);
    function _acceptAdmin() external virtual returns (uint256);
    function _setComptroller(ComptrollerInterface newComptroller) external virtual returns (uint256);
    function _setReserveFactor(uint256 newReserveFactorMantissa) external virtual returns (uint256);
    function _reduceReserves(uint256 reduceAmount) external virtual returns (uint256);
    function _setInterestRateModel(InterestRateModel newInterestRateModel) external virtual returns (uint256);
    function _setProtocolSeizeShare(uint256 newProtocolSeizeShareMantissa) external virtual returns (uint256);
}

contract TErc20Storage {
    /// @notice Underlying asset for this HToken
    address public underlying;
}

abstract contract HErc20Interface is TErc20Storage {
    /**
     * User Interface **
     */
    function mint(uint256 mintAmount) external virtual returns (uint256);
    function mintWithPermit(uint256 mintAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        virtual
        returns (uint256);
    function redeem(uint256 redeemTokens) external virtual returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external virtual returns (uint256);
    function borrow(uint256 borrowAmount) external virtual returns (uint256);
    function repayBorrow(uint256 repayAmount) external virtual returns (uint256);
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external virtual returns (uint256);
    function liquidateBorrow(address borrower, uint256 repayAmount, HTokenInterface hTokenCollateral)
        external
        virtual
        returns (uint256);
    function sweepToken(EIP20NonStandardInterface token) external virtual;

    /**
     * Admin Functions **
     */
    function _addReserves(uint256 addAmount) external virtual returns (uint256);
}

contract RDelegationStorage {
    /// @notice Implementation address for this contract
    address public implementation;
}

abstract contract HDelegatorInterface is RDelegationStorage {
    /// @notice Emitted when implementation is changed
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(address implementation_, bool allowResign, bytes memory becomeImplementationData)
        external
        virtual;
}

abstract contract HDelegateInterface is RDelegationStorage {
    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) external virtual;

    /// @notice Called by the delegator on a delegate to forfeit its responsibility
    function _resignImplementation() external virtual;
}
