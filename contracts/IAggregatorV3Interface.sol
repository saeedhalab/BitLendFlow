// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

interface IAggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        );
}