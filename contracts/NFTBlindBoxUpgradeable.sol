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
import "./libraries/MetadataLibrary.sol";
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

    // 用户已购买的盲盒（追加在末尾，避免移动已有存储槽）
    mapping(address => uint[]) private userBoxes;

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
        vrfHandler = VRFHandler(vrfHandlerAddress);

        maxSupply = _maxSupply;
        _baseTokenURI = baseURI;
        version = _version;
    }

    /**
     * @dev 购买盲盒
     * @notice 使用SaleManager模块验证购买条件，使用VRFHandler请求随机数
     */
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
        uint[] storage tokenIds = userBoxes[_msgSender()];
        tokenIds.push(tokenId);

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

    /**
     * @dev 设置 VRFHandler 地址（仅 owner）
     */
    function setVRFHandler(address _vrfHandler) external onlyOwner {
        vrfHandler = VRFHandler(_vrfHandler);
    }

    /**
     * @dev 设置最大供应量（仅 owner）
     */
    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
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

    /**
     * @dev 获取销售信息
     */
    function getSaleInfo()
        public
        view
        returns (
            bool active,
            SaleManager.SalePhase phase,
            uint256 currentPrice,
            uint256 maxWallet
        )
    {
        return (
            saleManager.saleActive(),
            saleManager.currentPhase(),
            saleManager.price(),
            saleManager.maxPerWallet()
        );
    }

    /**
     * @dev 获取tokenURI
     * @notice 优化：已揭示的 NFT 按需计算 URI，而不是从 storage 读取，节省 gas
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");

        // 如果已揭示，按需计算 URI（而不是从 storage 读取，节省 gas）
        if (blindBoxes[tokenId].revealed) {
            RarityLibrary.Rarity rarity = tokenRarity[tokenId];
            // 按需构建 URI，避免在 VRF 回调中存储完整字符串
            return MetadataLibrary.buildTokenURI(_baseTokenURI, rarity);
        }

        // 未揭示时返回盲盒URI（使用MetadataLibrary）
        return MetadataLibrary.buildBlindBoxURI(_baseTokenURI);
    }

    // ============ 元数据管理（使用库）============
    /**
     * @dev 设置基础URI
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev 获取基础URI
     */
    function baseURI() public view returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev 设置tokenURI
     */
    function _setTokenURI(uint256 tokenId, string memory uri) internal {
        _tokenURIs[tokenId] = uri;
    }

    // ============ 销售管理（委托给SaleManager）============
    /**
     * @dev 设置价格
     */
    function setPrice(uint256 _price) public onlyOwner {
        saleManager.setPrice(_price);
    }

    /**
     * @dev 设置销售状态
     */
    function setSaleActive(bool _active) public onlyOwner {
        saleManager.setSaleActive(_active);
    }

    /**
     * @dev 设置销售阶段
     */
    function setSalePhase(SaleManager.SalePhase _phase) public onlyOwner {
        saleManager.setSalePhase(_phase);
    }

    /**
     * @dev 设置每个钱包最大购买数
     */
    function setMaxPerWallet(uint256 _max) public onlyOwner {
        saleManager.setMaxPerWallet(_max);
    }

    /**
     * 获取当前用户所有购买的盲盒列表
     */
    function myTokenIds() public view returns (uint[] memory) {
        return userBoxes[_msgSender()];
    }

    // ============ 辅助函数 ============
    /**
     * @dev 提取资金
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Transfer failed");
    }

    uint256[50] private __gap;
}
