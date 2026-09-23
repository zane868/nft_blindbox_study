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

contract NFTBlindBoxUpgradeable is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    IVRFCallback
{
    // ============ 状态变量 ============
    uint256 public totalSupply;
    uint256 public maxSupply;

    string private _baseTokenURI;
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
        string memory baseURI
    ) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        maxSupply = _maxSupply;
        _baseTokenURI = baseURI;
    }
}
