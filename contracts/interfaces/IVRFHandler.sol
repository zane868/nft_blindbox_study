// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVRFHandler {
    /**
     * @dev 请求随机数
     * @param tokenId token ID
     * @param callbackContract 回调合约地址
     * @return requestId 请求ID
     */
    function requestRandomness(
        uint tokenId,
        address callbackContract
    ) external returns (uint requestId);
}

interface IVRFCallback {}
