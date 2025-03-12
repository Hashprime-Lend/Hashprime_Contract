// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "src/HErc20.sol";
import "src/EIP20Interface.sol";
import "src/Comptroller.sol";
import "src/oracles/CompositeOracle.sol";
import "src/irm/JumpRateModel.sol";

contract MarketState {
    struct MarketsInfo {
        uint256 tvl;
        uint256 ltv;
        uint256 totalSupply;
        uint256 totalBorrows;
        uint256 supplyRatePerBlock;
        uint256 borrowRatePerBlock;
        uint256 blocksPerYear;
        uint256 timestampsPerYear;
        address token;
        address underlying;
        string symbol;
        string underlyingSymbol;
    }

    Comptroller public comptroller;
    CompositeOracle public oracle;

    constructor(address _comptroller, address _oracle) {
        comptroller = Comptroller(_comptroller);
        oracle = CompositeOracle(_oracle);
    }

    function getActiveMarketsInfo() external view returns (MarketsInfo[] memory) {
        HToken[] memory allMarkets = comptroller.getAllMarkets();
        uint256 activeCount = 0;

        // 计算非弃用市场的数量
        for (uint256 i = 0; i < allMarkets.length; i++) {
            if (!comptroller.isDeprecated(allMarkets[i])) {
                activeCount++;
            }
        }

        // 创建结果数组
        MarketsInfo[] memory activeMarketsInfo = new MarketsInfo[](activeCount);
        uint256 index = 0;

        // 填充非弃用市场的数据
        for (uint256 i = 0; i < allMarkets.length; i++) {
            if (!comptroller.isDeprecated(allMarkets[i])) {
                HErc20 rToken = HErc20(address(allMarkets[i]));
                address underlying_addr = rToken.underlying();
                uint256 price = oracle.getPrice(rToken);
                string memory underlyingSymbol;
                EIP20Interface underlying = EIP20Interface(underlying_addr);
                uint256 blocksPerYear;
                uint256 timestampsPerYear;

                uint256 decimals = uint256(underlying.decimals());
                underlyingSymbol = underlying.symbol();
                timestampsPerYear = JumpRateModel(address(rToken.interestRateModel())).timestampsPerYear();

                uint256 tvl = rToken.getCash() * price / 10 ** decimals;
                uint256 totalSupply = rToken.totalSupply() * price / 10 ** decimals;
                uint256 totalBorrows = rToken.totalBorrows() * price / 10 ** decimals;
                uint256 supplyRatePerBlock = rToken.supplyRatePerBlock();
                uint256 borrowRatePerBlock = rToken.borrowRatePerBlock();
                (, uint256 ltv) = comptroller.markets(address(rToken));

                activeMarketsInfo[index] = MarketsInfo({
                    ltv: ltv,
                    tvl: tvl,
                    totalSupply: totalSupply,
                    totalBorrows: totalBorrows,
                    blocksPerYear: blocksPerYear,
                    timestampsPerYear: timestampsPerYear,
                    supplyRatePerBlock: supplyRatePerBlock,
                    borrowRatePerBlock: borrowRatePerBlock,
                    token: address(rToken),
                    underlying: rToken.underlying(),
                    symbol: rToken.symbol(),
                    underlyingSymbol: underlyingSymbol
                });

                index++;
            }
        }

        return activeMarketsInfo;
    }
}
