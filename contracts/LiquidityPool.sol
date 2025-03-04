// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

import "./ILendingFactory.sol";
import "./IERC20.sol";

import "./IAggregatorV3Interface.sol";

contract LiquidityPool {
    uint totalBorrowInUSD;
    uint totalBorrowTokens;
    uint256 public decimalUnit;
    uint validBorrowPercent;
    uint256 public maxLockTime;
    uint256 public minLockTime;
    address public lendingContract;
    address public token;
    address public priceOracle;
    address public coinPriceOracle;
    RateData public rateData;
    uint fee;

    struct RateData {
        uint256 baseRate;
        uint256 multiplier; // 20 ضریب تأثیر لگاریتمی
        uint256 timeMultiplier; //5
    }
    struct BorrowInfo {
        address user;
        uint collateralInUSD;
        uint coinAmount;
        uint startBorrowTime;
        uint borrowAmountInUSD;
        uint borrowAmountToken;
        uint marketRate;
        uint borrowRate;
        uint lockTime;
        uint fee;
        bool isRepay;
    }
    mapping(address => mapping(uint => BorrowInfo)) userBrrows;

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
        uint _decimalUnit,
        address _token,
        address _priceOracle
    ) {
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
        decimalUnit = _decimalUnit;
    }

    function getTokenPriceInUSD() public view returns (uint) {
        // فرض کنید تابع getLatestPrice() قیمت توکن را از اوراکل می‌گیرد
        (, int price, , , ) = IAggregatorV3Interface(priceOracle)
            .latestRoundData();
        return _scaleDecimal(uint(price), IERC20(token).decimals());
    }

    function deposit(uint _amount, uint _periodTime) public {
        require(
            _periodTime >= minLockTime && _periodTime <= maxLockTime,
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
            getMarketRate(_periodTime),
            rateData.baseRate
        );
        emit Deposit(token, msg.sender, _amount, _periodTime);
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

    function getMarketRate(uint256 lockTime) public view returns (uint256) {
        uint256 totalLiquidityInUSD = getTotalLiquidity(token);
        uint256 totalBorrows = getTotalBorrowInUSD();

        if (totalLiquidityInUSD == 0) return rateData.baseRate;

        uint256 utilization = (totalBorrows * 100) / totalLiquidityInUSD;

        // محاسبه لگاریتمی نرخ بهره
        uint256 precision = 1e18; // مقیاس‌دهی برای جلوگیری از گرد شدن

        uint256 logU = ((utilization * precision * 100) / (utilization + 10)) /
            precision;
        uint256 baseRateCalc = rateData.baseRate +
            (logU * rateData.multiplier) /
            100;

        // محاسبه اثر مدت زمان قفل
        uint256 lockBonus = (lockTime * rateData.timeMultiplier) / maxLockTime;

        return baseRateCalc + lockBonus;
    }

    function getBorrowRate(uint _lockTime) public view returns (uint) {
        uint marketRate = getMarketRate(_lockTime);
        return marketRate + fee;
    }

    function getTotalLiquidity(address _token) public view returns (uint) {
        uint256 tokenAmount = IERC20(_token).balanceOf(address(this));
        uint tokenPrice = getTokenPriceInUSD(); // دریافت قیمت توکن از اوراکل
        uint256 liquidityInUSD = (tokenAmount * tokenPrice) /
            (10 ** decimalUnit);
        return liquidityInUSD; // برگرداندن مقدار لیکوییدیتی به دلار
    }

    function getTotalBorrowInUSD() public view returns (uint) {
        return totalBorrowInUSD;
    }

    function borrow(uint _time) public payable {
        require(_time != 0, "invalid lock time");
        require(_time <= 60 days, "invalid lock time");
        (uint amountInUSD, ) = _calcCoinOracle(msg.value);
        uint validBorrowPercentUSD = (amountInUSD * validBorrowPercent) / 100;
        uint tokenPrice = getTokenPriceInUSD();
        uint borrowRate = getBorrowRate(_time);
        uint marketRate = getMarketRate(_time);
        uint lockTime = (_time * 1 days) + block.timestamp;
        uint amountBorrowTokens = validBorrowPercentUSD / tokenPrice;
        require(
            amountBorrowTokens <= IERC20(token).balanceOf(address(this)),
            "Insufficient liquidity"
        );
        uint borrowId = uint(
            keccak256(abi.encodePacked(msg.sender, msg.value, block.timestamp))
        );

        userBrrows[msg.sender][borrowId] = BorrowInfo(
            msg.sender,
            amountInUSD,
            msg.value,
            block.timestamp,
            validBorrowPercentUSD,
            amountBorrowTokens,
            marketRate,
            borrowRate,
            lockTime,
            fee,
            false
        );
        require(
            IERC20(token).transfer(msg.sender, amountBorrowTokens),
            "transfer was failed"
        );
    }

    function getBrrowRate(uint _time) public view returns (uint) {
        uint marketRate = getMarketRate(_time);
        return marketRate + fee;
    }

    function _calcCoinOracle(
        uint _amount
    ) private view returns (uint _priceInUSD, uint _coinPrice) {
        (address coinOracle, uint decimalCoin) = ILendingFactory(
            lendingContract
        ).getCoinOracleInfo();
        (, int price, , , ) = IAggregatorV3Interface(coinOracle)
            .latestRoundData();
        uint coinPrice = _scaleDecimal(uint(price), decimalCoin);
        uint priceInUSD = _amount * coinPrice;
        return (priceInUSD, coinPrice);
    }

    function _scaleDecimal(
        uint256 amount, // مقدار اصلی
        uint256 decimals // دسیمال اولیه
    ) private view returns (uint256) {
        if (decimals > decimalUnit) {
            // اگر دسیمال مقصد کوچکتر باشه، باید تقسیم کنیم
            uint256 scaleFactor = decimals - decimalUnit;
            return amount / (10 ** scaleFactor);
        } else if (decimals < decimalUnit) {
            // اگر دسیمال مقصد بزرگتر باشه، باید ضرب کنیم
            uint256 scaleFactor = decimalUnit - decimals;
            return amount * (10 ** scaleFactor);
        } else {
            // اگر دسیمال‌ها برابر باشن، همان مقدار رو برمی‌گردونه
            return amount;
        }
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
}
