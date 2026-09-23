// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import "../interfaces/IVRFHandler.sol";

contract VRFHandler is Initializable, OwnableUpgradeable, IVRFHandler {
    constructor() {}

    function requestRandomness(
        uint tokenId,
        address callbackContract
    ) external override returns (uint requestId) {}
}
