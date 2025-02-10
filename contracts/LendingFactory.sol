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
        uint marketRate;
        uint lendingStart;
        uint baseRate;
        address lendingToken;
        address liquidityPool;
    }

    mapping(address => LendingInfo) lendingUser;
    mapping(address => address) tokenLiquidity;
    mapping(address => mapping(address => mapping(uint => LendingInfo)))
        public userLendingInfo;
    mapping(address => uint) lendingLiquidityAmount;
    mapping(address => uint[]) userDepositsId;

    event CreateLiquidity(
        address liquidityContract,
        address _token,
        uint _baseRate
    );
    event Withdraw(address user, address token, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "called must be owner");
        _;
    }
    modifier onlyLiquidityPools() {
        bool isValid = false;

        for (uint i = 0; i < liquidityPools.length; i++) {
            if (liquidityPools[i] == msg.sender) {
                isValid = true;
                break;
            }
        }
        require(isValid, "just liquidityPools are called");
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
        uint _marketRate,
        uint _baseRate
    ) external onlyLiquidityPools {
        uint depositId = block.number + block.timestamp;
        userLendingInfo[_user][msg.sender][depositId] = LendingInfo(
            _amount,
            _luckPeriod,
            _marketRate,
            block.timestamp,
            _baseRate,
            _token,
            msg.sender
        );
        lendingLiquidityAmount[msg.sender] += _amount;
        userDepositsId[msg.sender].push(depositId);
    }

    function createLiquidityPool(
        address _token,
        uint _baseRate,
        uint _multiplier,
        uint _timeMultiplier,
        uint _maxLockTime,
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
                _oracleDecimal,
                _token,
                _priceOracle
            )
        );
        liquidityPools.push(contractAddress);

        tokenLiquidity[_token] = contractAddress;
        emit CreateLiquidity(contractAddress, _token, _baseRate);
    }

    function withdraw(uint _depositId, address _liquidity) public {
        require(isValidLiquidity(_liquidity), "liquidity is not valid");
        require(isValidDepositId(msg.sender, _depositId), "is not valid id");
        LendingInfo memory depositInfo = userLendingInfo[msg.sender][
            _liquidity
        ][_depositId];
        require(
            depositInfo.lockPeriod < block.timestamp,
            "not allowed to withdraw"
        );

        ///send request to liquidity contract for transfer tokens
        ILiquidityPool(_liquidity).unlockTokens(
            msg.sender,
            depositInfo.lendingToken,
            calculateRate(
                depositInfo.amount,
                depositInfo.marketRate,
                depositInfo.baseRate
            ) //calculate amount + rate
        );
        emit Withdraw(msg.sender, depositInfo.lendingToken, depositInfo.amount);
    }

    function calculateRate(
        uint _amount,
        uint _marketRate,
        uint _baseRate
    ) public pure returns (uint) {
        uint rate = (_marketRate > _baseRate) ? _marketRate : _baseRate;
        return _amount + ((rate * _amount) / 100);
    }

    function isValidLiquidity(
        address _liquidity
    ) public view returns (bool res) {
        for (uint i = 0; i < liquidityPools.length; i++) {
            if (_liquidity == liquidityPools[i]) {
                return true;
            }
        }
    }

    function isValidDepositId(
        address _user,
        uint _id
    ) public view returns (bool res) {
        uint[] memory ids = userDepositsId[_user];
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == _id) return true;
        }
    }
}
