// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

import "./ILiquidityPool.sol";
import "./LiquidityPool.sol";

contract LendingFactory {
    address liquidityContract;
    address owner;
    address[] liquidityPools;
    struct LendingInfo {
        uint amount;
        uint lockPeriod;
        uint lockEndTime;
        uint marketRate;
        uint baseRate;
        uint lendingStart;
        address lendingToken;
        address liquidityPool;
    }

    mapping(address => LendingInfo) lendingUser;
    mapping(address => mapping(uint => bool)) isDepositUser;
    mapping(address => bool) isValidLiquidity;
    mapping(address => address) tokenLiquidity;
    mapping(address => mapping(address => mapping(uint => LendingInfo)))
        public userLendingInfo;
    mapping(address => uint) lendingLiquidityAmount;
    mapping(address => uint[]) userDepositsId;

    event PoolCreated(
        address indexed pool,
        address indexed token,
        uint baseRate
    );
    event Withdraw(address user, address token, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "called must be owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerDeposit(
        address _user,
        address _token,
        uint _amount,
        uint _luckPeriod,
        uint _lockEndTime,
        uint _marketRate,
        uint _baseRate
    ) external {
        require(
            tokenLiquidity[_token] == msg.sender,
            "only liquidity pool contract call"
        );
        require(isValidLiquidity[msg.sender], "Not a valid liquidity pool");
        uint depositId = uint(
            keccak256(abi.encodePacked(_user, _amount, block.timestamp))
        );
        userLendingInfo[_user][msg.sender][depositId] = LendingInfo(
            _amount,
            _luckPeriod,
            _lockEndTime,
            _marketRate,
            _baseRate,
            block.timestamp,
            _token,
            msg.sender
        );
        isDepositUser[_user][depositId] = true;
        lendingLiquidityAmount[msg.sender] += _amount;
        userDepositsId[_user].push(depositId);
    }

    function createLiquidityPool(
        address _token,
        uint _baseRate,
        uint _multiplier,
        uint _timeMultiplier,
        uint _maxLockTime,
        uint _minLockTime,
        address _priceOracle,
        uint _oracleDecimal
    ) public onlyOwner {
        require(tokenLiquidity[_token] == address(0), "liquidity is exist");
        require(_token != address(0) && _priceOracle != address(0));
        require(_baseRate != 0);
        address contractAddress = address(
            new LiquidityPool(
                _baseRate,
                _multiplier,
                _timeMultiplier,
                _maxLockTime,
                _minLockTime,
                _oracleDecimal,
                _token,
                _priceOracle
            )
        );
        liquidityPools.push(contractAddress);
        isValidLiquidity[contractAddress] = true;
        tokenLiquidity[_token] = contractAddress;
        emit PoolCreated(contractAddress, _token, _baseRate);
    }

    function withdraw(uint _depositId, address _liquidity) public {
        require(isValidLiquidity[_liquidity], "liquidity is not valid");
        require(isDepositUser[msg.sender][_depositId], "is not valid id");
        LendingInfo memory depositInfo = userLendingInfo[msg.sender][
            _liquidity
        ][_depositId];
        require(
            depositInfo.lockEndTime <= block.timestamp,
            "not allowed to withdraw"
        );

        ///send request to liquidity contract for transfer tokens
        ILiquidityPool(_liquidity).unlockTokens(
            msg.sender,
            calculateRate(
                depositInfo.amount,
                depositInfo.marketRate,
                depositInfo.baseRate,
                depositInfo.lockPeriod
            ) //calculate amount + rate
        );
        emit Withdraw(msg.sender, depositInfo.lendingToken, depositInfo.amount);
    }

    function calculateRate(
        uint _amount,
        uint _marketRate,
        uint _baseRate,
        uint _lockPeriod
    ) public pure returns (uint) {
        uint rate = (_marketRate > _baseRate) ? _marketRate : _baseRate;
        uint timeInYears = _lockPeriod / 365 days;
        uint compoundInterest = _amount * ((1 + rate / 100) ** timeInYears);
        return compoundInterest;
    }
}
