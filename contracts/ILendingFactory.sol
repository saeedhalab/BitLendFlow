// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

interface ILendingFactory {
    

    function isValidToken(address _token) external returns (bool);

    function regiterDepoit(
        address _user,
        address _lendingToken,
        uint _amount,
        uint _luckPeriod,
        uint _marketRate,
        uint _basrRate
    ) external;
}
