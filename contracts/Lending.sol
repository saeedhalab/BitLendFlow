// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

contract Lending {
    address liquidityContract;
    address owner;
    struct LendingInfo {
        uint amount;
        uint lockPeriod;
        uint currentIntrestRate;
        uint lendingStart;
        address lendingToken;
    }

    mapping(address => LendingInfo) lendingUser;

    modifier onlyOwner() {
        require(msg.sender == owner, "called must be owner");
        _;
    }
    modifier onlyLiquidity() {
        require(
            msg.sender == liquidityContract,
            "called must be liquidityContract"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function regiterDepoit(
        address _user,
        uint _amount,
        uint _luckPeriod,
        address _lendingToken
    ) external onlyLiquidity {
        lendingUser[_user] = LendingInfo(
            _amount,
            _luckPeriod,
            getCurrentIntrestRate(),
            block.timestamp,
            _lendingToken
        );
    }

    function setLiquidityAddress(address _liquidity) public onlyOwner {
        require(_liquidity != address(0), "address can't be empty");
        liquidityContract = _liquidity;
    }

    function getCurrentIntrestRate() public pure returns (uint) {
        return 10;
    }

    function withdraw() public {
        LendingInfo memory info = lendingUser[msg.sender];
        require(
            info.lockPeriod + info.lendingStart < block.timestamp,
            "not allowed to withdraw"
        );
        ///send request to liquidity contract for transfer tokens
    }
}
