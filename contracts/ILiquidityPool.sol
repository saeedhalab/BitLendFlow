// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

interface ILiquidityPool {
    function unlockTokens(
        address _user,
        address _token,
        uint _amount
    ) external payable;
}
