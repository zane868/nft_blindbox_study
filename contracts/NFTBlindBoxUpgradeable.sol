// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

// 导入库和模块
import "./handlers/VRFHandler.sol";
import "./interfaces/IVRFHandler.sol"; // 导入 IVRFHandler 以使用 IVRFCallback 接口

import "./modules/SaleManager.sol"; //;
import "./modules/BlindBoxStorage.sol"; //;

using BlindBoxStorage for BlindBoxStorage.BlindBox;

contract NFTBlindBoxUpgradeable is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    IVRFCallback
{
    // ============ 事件定义 ============
    event BoxPurchased(address indexed buyer, uint256 indexed tokenId);
    event BoxRevealed(uint256 indexed tokenId, RarityLibrary.Rarity rarity);
    event RarityAssigned(uint256 indexed tokenId, RarityLibrary.Rarity rarity);

    // 稀有度映射
    mapping(uint256 => RarityLibrary.Rarity) public tokenRarity;
    mapping(uint256 => BlindBoxStorage.BlindBox) public blindBoxes;
    mapping(uint256 => string) private _tokenURIs;

    // ============ 状态变量 ============
    uint256 public totalSupply;

    //最大供应量
    uint256 public maxSupply;

    // 使用模块
    SaleManager public saleManager;
    VRFHandler public vrfHandler;

    string private _baseTokenURI;

    uint version;
    /**
     * @dev 初始化函数，在代理部署时调用
     * @param name NFT名称
     * @param symbol NFT符号
     * @param _maxSupply 最大供应量
     * @param saleManagerAddress SaleManager模块地址
     * @param vrfHandlerAddress VRFHandler模块地址
     * @param baseURI 基础URI
     * @notice 价格参数已移除，价格由SaleManager模块管理
     */
    function initialize(
        string memory name,
        string memory symbol,
        uint _maxSupply,
        address saleManagerAddress,
        address vrfHandlerAddress,
        string memory baseURI,
        uint _version
    ) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);
        saleManager = SaleManager(saleManagerAddress);

        maxSupply = _maxSupply;
        _baseTokenURI = baseURI;
        version = _version;
    }

    function purchaseBox() external payable virtual nonReentrant {
        uint userBalance = balanceOf(_msgSender());
        (bool canBuy, string memory reason) = saleManager.canPurchase(
            _msgSender(),
            userBalance,
            msg.value
        );

        require(canBuy, reason);

        require(totalSupply < maxSupply, "sold out");

        saleManager.recordWhitelistPurchase(_msgSender());

        uint tokenId = totalSupply;
        totalSupply++;

        //铸造NFT
        _safeMint(_msgSender(), tokenId);

        // 设置盲盒状态（使用存储库）
        blindBoxes[tokenId] = BlindBoxStorage.createBlindBox();

        // 使用VRFHandler请求随机数（传入当前合约地址作为回调）
        vrfHandler.requestRandomness(tokenId, address(this));

        emit BoxPurchased(msg.sender, tokenId);
    }

    // ============ UUPS升级授权 ============
    /**
     * @dev 授权升级函数，只有owner可以升级
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function getVersion() public view returns (uint) {
        return version;
    }

    function handleVRFCallback(
        uint256 requestId,
        uint256 tokenId,
        uint256 randomness
    ) external override {
        // 验证调用者（只验证调用者，revealBox 中会验证 token 存在，避免重复检查）
        require(msg.sender == address(vrfHandler), "Only VRF handler can call");

        // 使用RarityLibrary分配稀有度
        RarityLibrary.Rarity rarity = RarityLibrary.assignRarity(randomness);
        tokenRarity[tokenId] = rarity;
        emit RarityAssigned(tokenId, rarity);

        // 揭示盲盒（内部函数会验证 token 存在）
        revealBox(tokenId);
    }

    // ============ 盲盒揭示 ============
    /**
     * @dev 揭示盲盒（内部函数）
     * @notice 优化：不在回调中存储完整 URI，改为在 tokenURI() 函数中按需计算，以节省 gas
     */
    function revealBox(uint256 tokenId) internal {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(!blindBoxes[tokenId].revealed, "Already revealed");

        // 使用存储库的方法标记为已揭示
        BlindBoxStorage.BlindBox storage bliBox = blindBoxes[tokenId];
        bliBox.markAsRevealed();

        // 优化：不在回调中存储完整 URI，改为在 tokenURI() 中按需计算
        // 这样可以节省大量 gas（存储字符串非常昂贵）
        // URI 会在 tokenURI() 函数中根据 baseURI + rarity + tokenId 按需构建

        RarityLibrary.Rarity rarity = tokenRarity[tokenId];
        emit BoxRevealed(tokenId, rarity);
    }

    uint256[50] private __gap;
}
