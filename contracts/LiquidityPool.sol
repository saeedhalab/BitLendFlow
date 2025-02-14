// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

import "./ILendingFactory.sol";
import "./IERC20.sol";

import "./IAggregatorV3Interface.sol";

contract LiquidityPool {
    uint totalBorrow;
    uint public decimal;
    uint256 public maxLockTime;
    uint256 public minLockTime;
    address public lendingContract;
    address public token;
    address public priceOracle;
    RateData public rateData;

    struct RateData {
        uint256 baseRate;
        uint256 multiplier; // 20 ضریب تأثیر لگاریتمی
        uint256 timeMultiplier; //5
    }

    mapping(address => uint) userBalance;

    event Deposit(address token, address user, uint amount, uint time);
    event UnlockToken(address token, address user, uint amount);

    modifier onlyLendingContract() {
        require(msg.sender == lendingContract, "must be  lendingContract call");
        _;
    }

    constructor(
        uint _baseRate,
        uint _multiplier,
        uint _timeMultiplier,
        uint _maxLockTime,
        uint _minLockTime,
        uint _decimal,
        address _token,
        address _priceOracle
    ) {
        require(_maxLockTime != 0, "Max lock time too high");
        require(_maxLockTime != 0, "Max lock time too high");
        require(_minLockTime < _maxLockTime, "invalid input");
        lendingContract = msg.sender;
        rateData.baseRate = _baseRate;
        rateData.multiplier = _multiplier;
        rateData.timeMultiplier = _timeMultiplier;
        maxLockTime = _maxLockTime * 1 days;
        minLockTime = _minLockTime * 1 days;
        token = _token;
        priceOracle = _priceOracle;
        decimal = _decimal;
    }

    function getTokenPriceInUSD() public view returns (uint) {
        // فرض کنید تابع getLatestPrice() قیمت توکن را از اوراکل می‌گیرد
        (, int price, , , ) = IAggregatorV3Interface(priceOracle)
            .latestRoundData();
        return uint(price);
    }

    function deposit(uint _amount, uint _periodTime) public {
        require(
            _periodTime >= (minLockTime * 1 days) &&
                _periodTime <= (maxLockTime * 1 days),
            "invalid input"
        );
        require(_amount != 0, "not valid amount");
        require(
            IERC20(token).transferFrom(msg.sender, address(this), _amount),
            "failed to transfer from token"
        );
        uint lockEndTime = block.timestamp + _periodTime;
        userBalance[msg.sender] += _amount;
        ILendingFactory(lendingContract).registerDeposit(
            msg.sender,
            token,
            _amount,
            _periodTime,
            lockEndTime,
            getMarketRate(_periodTime, token),
            rateData.baseRate
        );
        emit Deposit(token, msg.sender, _amount, _periodTime);
    }

    function setMultiplier(
        uint _multiplier,
        uint _timeMultiplier
    ) public onlyLendingContract {
        require(_multiplier != 0 && _timeMultiplier != 0, "Invalid Multiplier");
        rateData.multiplier = _multiplier;
        rateData.timeMultiplier = _timeMultiplier;
    }

    function setBaseRate(uint _rate) public onlyLendingContract {
        require(_rate != 0, "base rate cannot be zero");
        rateData.baseRate = _rate;
    }

    function unlockTokens(
        address _user,
        uint _amount
    ) external payable onlyLendingContract {
        require(userBalance[_user] >= _amount, "Insufficient liquidity");
        userBalance[_user] -= _amount;
        require(IERC20(token).transfer(_user, _amount), "failed to transfer");
        emit UnlockToken(token, _user, _amount);
    }

    function getMarketRate(
        uint256 lockTime,
        address _token
    ) public view returns (uint256) {
        uint256 totalLiquidity = getTotalLiquidity(_token);
        uint256 totalBorrows = getTotalBorrows();

        if (totalLiquidity == 0) return rateData.baseRate;

        uint256 utilization = (totalBorrows * 100) / totalLiquidity;

        // محاسبه لگاریتمی نرخ بهره
        uint256 logU = (utilization * 100) / (utilization + 10);
        uint256 baseRateCalc = rateData.baseRate +
            (logU * rateData.multiplier) /
            100;

        // محاسبه اثر مدت زمان قفل
        uint256 lockBonus = (lockTime * rateData.timeMultiplier) / maxLockTime;

        return baseRateCalc + lockBonus;
    }

    function getTotalLiquidity(address _token) public view returns (uint) {
        uint256 tokenAmount = IERC20(_token).balanceOf(address(this));
        uint tokenPrice = getTokenPriceInUSD(); // دریافت قیمت توکن از اوراکل
        uint256 liquidityInUSD = (tokenAmount * tokenPrice) / (10 ** decimal);
        return liquidityInUSD; // برگرداندن مقدار لیکوییدیتی به دلار
    }

    function getTotalBorrows() public view returns (uint) {
        return totalBorrow;
    }

    function scaleOraclePrice(
        uint256 oraclePrice, // قیمت اوراکل
        uint256 oracleDecimals, // دسیمال‌های اوراکل
        uint256 tokenDecimals // دسیمال‌های توکن
    ) public pure returns (uint256) {
        if (oracleDecimals > tokenDecimals) {
            // اگر دسیمال اوراکل بیشتر از دسیمال توکن باشد
            uint256 scaleFactor = oracleDecimals - tokenDecimals;
            // مقیاس‌دهی اوراکل به سمت پایین
            return oraclePrice / (10 ** scaleFactor);
        } else if (oracleDecimals < tokenDecimals) {
            // اگر دسیمال اوراکل کمتر از دسیمال توکن باشد
            uint256 scaleFactor = tokenDecimals - oracleDecimals;
            // مقیاس‌دهی اوراکل به سمت بالا
            return oraclePrice * (10 ** scaleFactor);
        } else {
            // اگر دسیمال‌ها برابر باشند، بدون تغییر باز می‌گردد
            return oraclePrice;
        }
    }
}
