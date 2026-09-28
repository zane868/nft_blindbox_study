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
    event UserDataClearing(
        address indexed user,
        uint256 remainingPurchases,
        uint256 scanCursor
    );
    event UserDataCleared(address indexed user);
    event ClearedTokenCallbackIgnored(uint256 indexed tokenId);

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

    // 每位原始买家的当前轮次：按成功回调顺序记录，最多 8 个
    mapping(address => uint[]) private userBoxesRound;

    // 购买时绑定，转移 NFT 不改变保底归属。升级前的旧盲盒为零地址。
    mapping(uint256 => address) public tokenBuyer;

    // 清理任务每笔交易最多处理 100 条记录；任务期间禁止铸造/转账。
    address public clearingUser;
    uint256 public cleanupCursor;
    uint256 private cleanupUpperBound;
    mapping(uint256 => bool) public clearedTokens;
    // ERC721 的 operator mapping 不可枚举，通过版本使旧授权失效。
    mapping(address => uint256) private approvalEpoch;
    mapping(address => mapping(address => uint256))
        private operatorApprovalEpoch;

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
        require(clearingUser == address(0), "User cleanup in progress");
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

        // 在 ERC721 接收方回调之前固定原始买家
        tokenBuyer[tokenId] = _msgSender();

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

    ///增加 "买X个盲盒必定有Y个Z等级的盲盒" 逻辑,买3次必得稀有，5次必得史诗，8次必得传说
    ///在实际的业务场景中业务会更加复杂，这里只是单纯的对技术进行研究，不做更加严谨的业务设计
    /// @dev 每位原始买家按成功回调顺序，每 8 个一轮；高等级满足低等级保底。
    function handleVRFCallback(
        uint256 /* requestId */,
        uint256 tokenId,
        uint256 randomness
    ) external override {
        require(msg.sender == address(vrfHandler), "Only VRF handler can call");
        if (clearedTokens[tokenId]) {
            emit ClearedTokenCallbackIgnored(tokenId);
            return;
        }
        _requireOwned(tokenId);
        require(!blindBoxes[tokenId].revealed, "Already revealed");

        // 每次都先抽奖；保底只能提高等级，不能覆盖更好的随机结果。
        RarityLibrary.Rarity rarity = RarityLibrary.assignRarity(randomness);
        address buyer = tokenBuyer[tokenId];
        if (buyer != address(0)) {
            uint[] storage round = userBoxesRound[buyer];
            // 第 9 次回调开始新一轮。旧数组即使意外超过 8，也不会无限增长。
            if (round.length >= 8) {
                delete userBoxesRound[buyer];
            }
            uint256 position = round.length + 1;
            RarityLibrary.Rarity minimum = RarityLibrary.Rarity.Common;
            if (position == 3) {
                minimum = RarityLibrary.Rarity.Rare;
            } else if (position == 5) {
                minimum = RarityLibrary.Rarity.Epic;
            } else if (position == 8) {
                minimum = RarityLibrary.Rarity.Legendary;
            }

            // 仅在本次随机结果未达标时，检查本轮之前的结果。
            if (rarity < minimum && !hitRarity(round, minimum)) {
                rarity = minimum;
            }
            round.push(tokenId);
        }

        tokenRarity[tokenId] = rarity;
        emit RarityAssigned(tokenId, rarity);
        revealBox(tokenId);
    }

    function hitRarity(
        uint[] storage roundArray,
        RarityLibrary.Rarity minimum
    ) private view returns (bool) {
        uint256 length = roundArray.length;
        for (uint256 i = 0; i < length; i++) {
            if (tokenRarity[roundArray[i]] >= minimum) {
                return true;
            }
        }
        return false;
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

    /**
     * 获取用户轮次的盲盒列表
     */
    function myUserBoxesRound() public view returns (uint[] memory) {
        return userBoxesRound[_msgSender()];
    }

    /**
     * @notice 清空用户数据，包括已转出的购买 NFT 和当前持有的 NFT。
     * @dev 重复调用，直到返回 true / clearingUser 为零。每次最多处理 100 条。
     * SaleManager 必须已升级且 owner 为本 NFT 代理。历史事件不可删除。
     */
    function clearUserData(
        address user
    ) external onlyOwner nonReentrant returns (bool finished) {
        require(user != address(0), "Invalid user");
        if (clearingUser == address(0)) {
            require(
                saleManager.owner() == address(this),
                "NFT must own SaleManager"
            );
            clearingUser = user;
            cleanupUpperBound = totalSupply;
            cleanupCursor = 0;
        } else {
            require(clearingUser == user, "Finish current cleanup first");
        }

        uint256 budget = 100;
        uint[] storage purchases = userBoxes[user];
        // 先逐个弹出购买记录，兼容升级前没有 tokenBuyer 的旧 NFT。
        while (purchases.length > 0 && budget > 0) {
            uint256 tokenId = purchases[purchases.length - 1];
            purchases.pop();
            _clearTokenData(tokenId);
            budget--;
        }
        // 再扫描当前持有的 NFT，包括别人转入的。totalSupply 保持为递增编号。
        while (
            purchases.length == 0 &&
            cleanupCursor < cleanupUpperBound &&
            budget > 0
        ) {
            uint256 tokenId = cleanupCursor++;
            if (_ownerOf(tokenId) == user || tokenBuyer[tokenId] == user) {
                _clearTokenData(tokenId);
            }
            budget--;
        }
        if (purchases.length > 0 || cleanupCursor < cleanupUpperBound) {
            emit UserDataClearing(user, purchases.length, cleanupCursor);
            return false;
        }

        delete userBoxesRound[user];
        approvalEpoch[user]++;
        saleManager.clearUserData(user);
        delete clearingUser;
        delete cleanupCursor;
        delete cleanupUpperBound;
        emit UserDataCleared(user);
        return true;
    }

    function _clearTokenData(uint256 tokenId) private {
        if (_ownerOf(tokenId) != address(0)) {
            _burn(tokenId); // 同时清理单币授权并更新当前持有人的余额
        }
        delete tokenRarity[tokenId];
        delete blindBoxes[tokenId];
        delete _tokenURIs[tokenId];
        delete tokenBuyer[tokenId];
        // 墓碑用于接收迟到回调；不复用 tokenId，防止旧请求污染新 NFT。
        clearedTokens[tokenId] = true;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        require(
            clearingUser == address(0) || to == address(0),
            "User cleanup in progress"
        );
        return super._update(to, tokenId, auth);
    }

    function isApprovedForAll(
        address account,
        address operator
    ) public view override returns (bool) {
        return
            super.isApprovedForAll(account, operator) &&
            operatorApprovalEpoch[account][operator] == approvalEpoch[account];
    }

    function _setApprovalForAll(
        address account,
        address operator,
        bool approved
    ) internal override {
        require(clearingUser != account, "User cleanup in progress");
        operatorApprovalEpoch[account][operator] = approvalEpoch[account];
        super._setApprovalForAll(account, operator, approved);
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

    // 保底占用 2 槽，清理任务及授权版本占用 6 槽
    uint256[42] private __gap;
}
