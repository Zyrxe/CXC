// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Presale is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    IERC20 public token;
    address payable public wallet;

    // Presale parameters
    uint256 public tokenPrice = 1259 * 10**8; // $12.59 in USD (assuming 8 decimals for USD price oracle)
    uint256 public softCap = 5000000 * 10**8; // $5,000,000 in USD
    uint256 public hardCap = 20000000 * 10**8; // $20,000,000 in USD
    uint256 public minContribution = 100 * 10**8; // $100 minimum
    uint256 public maxContribution = 100000 * 10**8; // $100,000 maximum

    // Vesting parameters
    uint256 public constant VESTING_DURATION = 365 days; // 1 year
    uint256 public vestingStart;

    // State
    uint256 public totalRaised;
    uint256 public tokensSold;
    bool public presaleEnded;
    bool public presaleSuccessful;

    // User contributions
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAllocations;
    mapping(address => uint256) public claimedTokens;

    // Events
    event Contribution(address indexed contributor, uint256 amount, uint256 tokens);
    event TokensClaimed(address indexed claimer, uint256 amount);
    event PresaleEnded(bool successful);
    event WalletUpdated(address newWallet);

    constructor(address _token, address payable _wallet) {
        token = IERC20(_token);
        wallet = _wallet;
        vestingStart = block.timestamp + VESTING_DURATION;
    }

    function contribute() external payable nonReentrant whenNotPaused {
        require(!presaleEnded, "Presale has ended");
        require(msg.value >= minContribution, "Contribution below minimum");
        require(contributions[msg.sender] + msg.value <= maxContribution, "Contribution exceeds maximum");
        require(totalRaised + msg.value <= hardCap, "Hard cap reached");

        // Calculate tokens to allocate
        uint256 tokensToAllocate = msg.value.mul(10**18).div(tokenPrice);

        // Update state
        contributions[msg.sender] = contributions[msg.sender].add(msg.value);
        tokenAllocations[msg.sender] = tokenAllocations[msg.sender].add(tokensToAllocate);
        totalRaised = totalRaised.add(msg.value);
        tokensSold = tokensSold.add(tokensToAllocate);

        // Transfer ETH to wallet
        wallet.transfer(msg.value);

        emit Contribution(msg.sender, msg.value, tokensToAllocate);
    }

    function claimTokens() external nonReentrant {
        require(presaleEnded, "Presale has not ended yet");
        require(presaleSuccessful, "Presale was not successful");
        require(block.timestamp >= vestingStart, "Vesting period has not started yet");
        require(tokenAllocations[msg.sender] > 0, "No tokens to claim");
        require(claimedTokens[msg.sender] < tokenAllocations[msg.sender], "All tokens already claimed");

        uint256 tokensToClaim = tokenAllocations[msg.sender].sub(claimedTokens[msg.sender]);
        claimedTokens[msg.sender] = tokenAllocations[msg.sender];

        require(token.transfer(msg.sender, tokensToClaim), "Token transfer failed");

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    function endPresale() external onlyOwner {
        require(!presaleEnded, "Presale already ended");

        presaleEnded = true;
        presaleSuccessful = totalRaised >= softCap;

        emit PresaleEnded(presaleSuccessful);
    }

    function refund() external nonReentrant {
        require(presaleEnded, "Presale has not ended yet");
        require(!presaleSuccessful, "Presale was successful, no refunds");
        require(contributions[msg.sender] > 0, "No contribution to refund");

        uint256 refundAmount = contributions[msg.sender];
        contributions[msg.sender] = 0;

        payable(msg.sender).transfer(refundAmount);
    }

    function setTokenPrice(uint256 newPrice) external onlyOwner {
        require(!presaleEnded, "Presale has ended");
        tokenPrice = newPrice;
    }

    function setWallet(address payable newWallet) external onlyOwner {
        wallet = newWallet;
        emit WalletUpdated(newWallet);
    }

    function setVestingStart(uint256 newStart) external onlyOwner {
        require(!presaleEnded, "Presale has ended");
        vestingStart = newStart;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawUnsoldTokens() external onlyOwner {
        require(presaleEnded, "Presale has not ended yet");
        uint256 unsoldTokens = token.balanceOf(address(this));
        require(token.transfer(wallet, unsoldTokens), "Transfer failed");
    }
}
