// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TAKULAI is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Token details
    string public constant NAME = "TAKULAI";
    string public constant SYMBOL = "TKI";
    uint8 public constant DECIMALS = 18;
    uint256 public constant TOTAL_SUPPLY = 1000000000 * (10**18); // 1,000,000,000 TKI

    // Distribution percentages (in basis points, 10000 = 100%)
    uint256 public constant DEVELOPER_PERCENTAGE = 4000; // 40%
    uint256 public constant PRESALE_PERCENTAGE = 2500; // 25%
    uint256 public constant LIQUIDITY_PERCENTAGE = 1500; // 15%
    uint256 public constant MARKETING_PERCENTAGE = 200; // 2%
    uint256 public constant BURN_RESERVE_PERCENTAGE = 1800; // 18%

    // Wallets
    address public developerWallet;
    address public presaleWallet;
    address public liquidityWallet;
    address public marketingWallet;
    address public burnReserveWallet;

    // Transaction limits
    uint256 public maxBuyAmount = 5000 * (10**18); // 5,000 TKI
    uint256 public maxSellAmount = 1000 * (10**18); // 1,000 TKI
    uint256 public cooldownPeriod = 60; // 1 minute in seconds

    // Burn mechanism
    uint256 public burnRate = 500; // 5% in basis points
    mapping(address => uint256) public lastTransactionTime;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public isExcludedFromBurn;

    // Events
    event BurnReserveReplenished(uint256 amount);
    event BurnRateUpdated(uint256 newRate);
    event MaxBuyAmountUpdated(uint256 newAmount);
    event MaxSellAmountUpdated(uint256 newAmount);
    event CooldownPeriodUpdated(uint256 newPeriod);

    constructor(
        address _developerWallet,
        address _presaleWallet,
        address _liquidityWallet,
        address _marketingWallet,
        address _burnReserveWallet
    ) ERC20(NAME, SYMBOL) {
        require(_developerWallet != address(0), "Developer wallet cannot be zero address");
        require(_presaleWallet != address(0), "Presale wallet cannot be zero address");
        require(_liquidityWallet != address(0), "Liquidity wallet cannot be zero address");
        require(_marketingWallet != address(0), "Marketing wallet cannot be zero address");
        require(_burnReserveWallet != address(0), "Burn reserve wallet cannot be zero address");

        developerWallet = _developerWallet;
        presaleWallet = _presaleWallet;
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;
        burnReserveWallet = _burnReserveWallet;

        // Mint total supply
        _mint(msg.sender, TOTAL_SUPPLY);

        // Distribute tokens
        uint256 developerAmount = TOTAL_SUPPLY.mul(DEVELOPER_PERCENTAGE).div(10000);
        uint256 presaleAmount = TOTAL_SUPPLY.mul(PRESALE_PERCENTAGE).div(10000);
        uint256 liquidityAmount = TOTAL_SUPPLY.mul(LIQUIDITY_PERCENTAGE).div(10000);
        uint256 marketingAmount = TOTAL_SUPPLY.mul(MARKETING_PERCENTAGE).div(10000);
        uint256 burnReserveAmount = TOTAL_SUPPLY.mul(BURN_RESERVE_PERCENTAGE).div(10000);

        _transfer(msg.sender, developerWallet, developerAmount);
        _transfer(msg.sender, presaleWallet, presaleAmount);
        _transfer(msg.sender, liquidityWallet, liquidityAmount);
        _transfer(msg.sender, marketingWallet, marketingAmount);
        _transfer(msg.sender, burnReserveWallet, burnReserveAmount);

        // Exclude owner and system wallets from limits and burn
        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[developerWallet] = true;
        isExcludedFromLimits[presaleWallet] = true;
        isExcludedFromLimits[liquidityWallet] = true;
        isExcludedFromLimits[marketingWallet] = true;
        isExcludedFromLimits[burnReserveWallet] = true;

        isExcludedFromBurn[msg.sender] = true;
        isExcludedFromBurn[developerWallet] = true;
        isExcludedFromBurn[presaleWallet] = true;
        isExcludedFromBurn[liquidityWallet] = true;
        isExcludedFromBurn[marketingWallet] = true;
        isExcludedFromBurn[burnReserveWallet] = true;
    }

    function transfer(address recipient, uint256 amount) public override nonReentrant returns (bool) {
        _validateTransfer(msg.sender, recipient, amount);
        _processBurn(msg.sender, amount);
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override nonReentrant returns (bool) {
        _validateTransfer(sender, recipient, amount);
        _processBurn(sender, amount);
        return super.transferFrom(sender, recipient, amount);
    }

    function _validateTransfer(address sender, address recipient, uint256 amount) internal view {
        if (isExcludedFromLimits[sender] || isExcludedFromLimits[recipient]) {
            return;
        }

        // Check cooldown
        require(block.timestamp >= lastTransactionTime[sender].add(cooldownPeriod), "Transfer in cooldown period");

        // Check max buy/sell limits
        // Note: In a real implementation, you'd need to determine if this is a buy or sell
        // For simplicity, we'll just check against the higher limit
        require(amount <= maxBuyAmount, "Transfer amount exceeds maximum limit");
    }

    function _processBurn(address sender, uint256 amount) internal {
        if (isExcludedFromBurn[sender]) {
            return;
        }

        uint256 burnAmount = amount.mul(burnRate).div(10000);
        if (burnAmount > 0 && balanceOf(burnReserveWallet) >= burnAmount) {
            _transfer(burnReserveWallet, address(0), burnAmount);
            lastTransactionTime[sender] = block.timestamp;
        }
    }

    // Owner functions
    function topUpBurnReserve(uint256 amount) external onlyOwner {
        require(balanceOf(marketingWallet) >= amount, "Insufficient balance in marketing wallet");
        _transfer(marketingWallet, burnReserveWallet, amount);
        emit BurnReserveReplenished(amount);
    }

    function updateBurnRate(uint256 newRate) external onlyOwner {
        require(newRate <= 1000, "Burn rate cannot exceed 10%");
        burnRate = newRate;
        emit BurnRateUpdated(newRate);
    }

    function updateMaxBuyAmount(uint256 newAmount) external onlyOwner {
        maxBuyAmount = newAmount;
        emit MaxBuyAmountUpdated(newAmount);
    }

    function updateMaxSellAmount(uint256 newAmount) external onlyOwner {
        maxSellAmount = newAmount;
        emit MaxSellAmountUpdated(newAmount);
    }

    function updateCooldownPeriod(uint256 newPeriod) external onlyOwner {
        cooldownPeriod = newPeriod;
        emit CooldownPeriodUpdated(newPeriod);
    }

    function excludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    function excludeFromBurn(address account, bool excluded) external onlyOwner {
        isExcludedFromBurn[account] = excluded;
    }

    function setSystemWallets(
        address _developerWallet,
        address _presaleWallet,
        address _liquidityWallet,
        address _marketingWallet,
        address _burnReserveWallet
    ) external onlyOwner {
        require(_developerWallet != address(0), "Developer wallet cannot be zero address");
        require(_presaleWallet != address(0), "Presale wallet cannot be zero address");
        require(_liquidityWallet != address(0), "Liquidity wallet cannot be zero address");
        require(_marketingWallet != address(0), "Marketing wallet cannot be zero address");
        require(_burnReserveWallet != address(0), "Burn reserve wallet cannot be zero address");

        developerWallet = _developerWallet;
        presaleWallet = _presaleWallet;
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;
        burnReserveWallet = _burnReserveWallet;
    }
}
