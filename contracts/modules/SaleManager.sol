// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SaleManager is Initializable, OwnableUpgradeable {
    // ============ 枚举 ============
    ///@dev 销售阶段
    enum SalePhase {
        NotStarted,
        WhiteList,
        Public
    }

    // ============ 状态变量 ============
    bool public saleActive;
    SalePhase public currentPhase;
    uint public price;
    uint public maxPerWallet;
    uint public constant whitelistMaxming = 3;

    //白名单
    mapping(address => bool) public whitelist;
    mapping(address => uint) public whitelistMinted;

    // ============ 事件 ============
    event SalePhaseChanged(address indexed user, SalePhase newPhase);
    event PriceUpdated(address indexed user, uint256 newPrice);
    event MaxPerWalletUpdated(address indexed user, uint256 newMax);
    event WhitelistAdded(address indexed user, address[] addresses);
    event WhitelistRemoved(address indexed user, address[] addresses);
    event WhitelistMinted(
        address indexed owner,
        address indexed user,
        uint256 count
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(uint _price, uint _maxPerWallet) public initializer {
        __Ownable_init(msg.sender);
        price = _price;
        maxPerWallet = _maxPerWallet;
        currentPhase = SalePhase.NotStarted;
        saleActive = false;
    }

    function setSaleActive(bool _active) external onlyOwner {
        saleActive = _active;
    }

    function setSalePhase(SalePhase _phase) external onlyOwner {
        currentPhase = _phase;
        saleActive = (_phase != SalePhase.NotStarted);
        emit SalePhaseChanged(_msgSender(), _phase);
    }

    function setPrice(uint _price) external onlyOwner {
        price = _price;
        emit PriceUpdated(_msgSender(), _price);
    }

    function setMaxPerWallet(uint _max) external onlyOwner {
        maxPerWallet = _max;
        emit MaxPerWalletUpdated(_msgSender(), _max);
    }

    function addWhitelist(address[] memory addresses) external onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
        emit WhitelistAdded(_msgSender(), addresses);
    }

    function removeWhiteList(address[] memory addresses) external onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = false;
        }
        emit WhitelistRemoved(_msgSender(), addresses);
    }

    function canPurchase(
        address user,
        uint userBalance,
        uint payment
    ) external view returns (bool, string memory) {
        if (!saleActive) {
            return (false, "Sale not active");
        }
        if (payment < price) {
            return (false, "Insufficient payment");
        }
        if (userBalance >= maxPerWallet) {
            return (false, "Max per wallet reached");
        }
        if (currentPhase == SalePhase.WhiteList) {
            if (!whitelist[user]) {
                return (false, "Not on the whitelist");
            }
            if (whitelistMinted[user] >= whitelistMaxming) {
                return (false, "Whitelist mint limit reached");
            }
        }
        return (true, "");
    }

    function recordWhitelistPurchase(address user) external {
        if (currentPhase == SalePhase.WhiteList) {
            whitelistMinted[user]++;
            emit WhitelistMinted(_msgSender(), user, whitelistMinted[user]);
        }
    }

    uint256[50] private __gap;
}
