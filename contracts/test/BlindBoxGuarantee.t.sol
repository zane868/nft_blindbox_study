// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NFTBlindBoxUpgradeable} from "../NFTBlindBoxUpgradeable.sol";
import {SaleManager} from "../modules/SaleManager.sol";
import {VRFHandler} from "../handlers/VRFHandler.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {RarityLibrary} from "../libraries/RarityLibrary.sol";

// 只替代异步随机数服务，购买、代理存储和揭晓均执行真实合约逻辑。
contract GuaranteeVRFStub {
    function requestRandomness(
        uint256 tokenId,
        address
    ) external pure returns (uint256) {
        return tokenId + 1;
    }
}

contract BlindBoxGuaranteeTest is Test {
    NFTBlindBoxUpgradeable private nft;
    GuaranteeVRFStub private handler;
    SaleManager private sale;
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        SaleManager saleImpl = new SaleManager();
        sale = SaleManager(
            address(
                new ERC1967Proxy(
                    address(saleImpl),
                    abi.encodeCall(SaleManager.initialize, (0, 100))
                )
            )
        );
        sale.setSalePhase(SaleManager.SalePhase.Public);
        handler = new GuaranteeVRFStub();
        NFTBlindBoxUpgradeable impl = new NFTBlindBoxUpgradeable();
        nft = NFTBlindBoxUpgradeable(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        NFTBlindBoxUpgradeable.initialize,
                        (
                            "BlindBox",
                            "BOX",
                            1000,
                            address(sale),
                            address(handler),
                            "ipfs://test",
                            1
                        )
                    )
                )
            )
        );
        sale.transferOwnership(address(nft));
    }

    function buy(address buyer) private returns (uint256 id) {
        id = nft.totalSupply();
        vm.prank(buyer);
        nft.purchaseBox();
    }

    function fulfill(uint256 id, uint256 randomness) private {
        vm.prank(address(handler));
        nft.handleVRFCallback(id + 1, id, randomness);
    }

    function assertRarity(
        uint256 id,
        RarityLibrary.Rarity expected
    ) private view {
        assertEq(uint256(nft.tokenRarity(id)), uint256(expected));
    }

    function test_ThresholdsAndSecondRound() public {
        for (uint256 i = 0; i < 16; i++) {
            uint256 id = buy(alice);
            fulfill(id, 9000); // 普通随机结果
            uint256 position = (i % 8) + 1;
            RarityLibrary.Rarity expected = RarityLibrary.Rarity.Common;
            if (position == 3) expected = RarityLibrary.Rarity.Rare;
            if (position == 5) expected = RarityLibrary.Rarity.Epic;
            if (position == 8) expected = RarityLibrary.Rarity.Legendary;
            assertRarity(id, expected);
            (, bool revealed, , ) = nft.blindBoxes(id);
            assertTrue(revealed);
        }
    }

    function test_EarlyLegendarySatisfiesAllMilestones() public {
        fulfill(buy(alice), 0);
        for (uint256 i = 1; i < 8; i++) {
            uint256 id = buy(alice);
            fulfill(id, 9000);
            assertRarity(id, RarityLibrary.Rarity.Common);
        }
    }

    function test_EarlyRareDoesNotSatisfyEpic() public {
        fulfill(buy(alice), 2000);
        fulfill(buy(alice), 9000);
        uint256 third = buy(alice);
        fulfill(third, 9000);
        assertRarity(third, RarityLibrary.Rarity.Common);
        fulfill(buy(alice), 9000);
        uint256 fifth = buy(alice);
        fulfill(fifth, 9000);
        assertRarity(fifth, RarityLibrary.Rarity.Epic);
    }

    function test_RandomLegendaryIsNotDowngradedAtRareMilestone() public {
        fulfill(buy(alice), 9000);
        fulfill(buy(alice), 9000);
        uint256 third = buy(alice);
        fulfill(third, 0);
        assertRarity(third, RarityLibrary.Rarity.Legendary);
    }

    function test_UsersHaveIndependentRounds() public {
        fulfill(buy(alice), 9000);
        fulfill(buy(alice), 9000);
        uint256 firstBob = buy(bob);
        fulfill(firstBob, 9000);
        assertRarity(firstBob, RarityLibrary.Rarity.Common);
        uint256 thirdAlice = buy(alice);
        fulfill(thirdAlice, 9000);
        assertRarity(thirdAlice, RarityLibrary.Rarity.Rare);
    }

    function test_OutOfOrderCallbacksUseArrivalOrder() public {
        uint256 first = buy(alice);
        uint256 second = buy(alice);
        uint256 third = buy(alice);
        fulfill(third, 9000);
        fulfill(second, 9000);
        fulfill(first, 9000);
        assertRarity(third, RarityLibrary.Rarity.Common);
        assertRarity(first, RarityLibrary.Rarity.Rare);
    }

    function test_TransferKeepsOriginalBuyerRound() public {
        fulfill(buy(alice), 9000);
        fulfill(buy(alice), 9000);
        uint256 third = buy(alice);
        vm.prank(alice);
        nft.transferFrom(alice, bob, third);
        fulfill(third, 9000);
        assertRarity(third, RarityLibrary.Rarity.Rare);
        assertEq(nft.tokenBuyer(third), alice);
        uint256 firstBob = buy(bob);
        fulfill(firstBob, 9000);
        assertRarity(firstBob, RarityLibrary.Rarity.Common);
    }

    function test_DuplicateCallbackDoesNotAdvanceRound() public {
        uint256 first = buy(alice);
        fulfill(first, 9000);
        vm.expectRevert(bytes("Already revealed"));
        fulfill(first, 0);
        uint256 second = buy(alice);
        fulfill(second, 9000);
        assertRarity(second, RarityLibrary.Rarity.Common);
        uint256 third = buy(alice);
        fulfill(third, 9000);
        assertRarity(third, RarityLibrary.Rarity.Rare);
    }

    function test_UnauthorizedCallbackRejected() public {
        uint256 id = buy(alice);
        vm.prank(bob);
        vm.expectRevert(bytes("Only VRF handler can call"));
        nft.handleVRFCallback(1, id, 0);
    }

    function test_UnknownTokenRejected() public {
        vm.prank(address(handler));
        vm.expectRevert(
            abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 99)
        );
        nft.handleVRFCallback(1, 99, 0);
    }

    function assertCleared(uint256 id) private {
        vm.expectRevert(
            abi.encodeWithSignature("ERC721NonexistentToken(uint256)", id)
        );
        nft.ownerOf(id);
        vm.expectRevert(
            abi.encodeWithSignature("ERC721NonexistentToken(uint256)", id)
        );
        nft.tokenURI(id);
        assertEq(nft.tokenBuyer(id), address(0));
        assertRarity(id, RarityLibrary.Rarity.Common);
        (
            bool purchased,
            bool revealed,
            uint256 purchasedAt,
            uint256 revealedAt
        ) = nft.blindBoxes(id);
        assertFalse(purchased);
        assertFalse(revealed);
        assertEq(purchasedAt, 0);
        assertEq(revealedAt, 0);
    }

    function test_ClearBurnsPurchasedTransferredOutAndReceivedTokens() public {
        uint256 first = buy(alice);
        uint256 transferred = buy(alice);
        uint256 received = buy(bob);
        uint256 unrelated = buy(bob);
        fulfill(first, 0);
        fulfill(unrelated, 1000);
        vm.prank(alice);
        nft.transferFrom(alice, bob, transferred);
        vm.prank(bob);
        nft.transferFrom(bob, alice, received);
        vm.prank(alice);
        nft.approve(bob, first);
        assertTrue(nft.clearUserData(alice));
        assertCleared(first);
        assertCleared(transferred);
        assertCleared(received);
        assertEq(nft.ownerOf(unrelated), bob);
        assertRarity(unrelated, RarityLibrary.Rarity.Epic);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.totalSupply(), 4); // 不复用被删除的编号
        vm.prank(alice);
        assertEq(nft.myTokenIds().length, 0);
        fulfill(transferred, 0); // 迟到回调正常返回，不恢复数据
        assertCleared(transferred);
    }

    function test_ClearResetsGuaranteeAndAllowsFreshPurchases() public {
        fulfill(buy(alice), 9000);
        fulfill(buy(alice), 9000);
        assertTrue(nft.clearUserData(alice));
        for (uint256 i = 0; i < 3; i++) {
            uint256 id = buy(alice);
            assertEq(id, i + 2);
            fulfill(id, 9000);
            assertRarity(
                id,
                i == 2 ? RarityLibrary.Rarity.Rare : RarityLibrary.Rarity.Common
            );
        }
        vm.prank(alice);
        assertEq(nft.myTokenIds().length, 3);
    }

    function test_ClearWhitelistAndOperatorApprovals() public {
        address[] memory users = new address[](1);
        users[0] = alice;
        vm.prank(address(nft));
        sale.addWhitelist(users);
        nft.setSalePhase(SaleManager.SalePhase.WhiteList);
        buy(alice);
        assertEq(sale.whitelistMinted(alice), 1);
        vm.prank(alice);
        nft.setApprovalForAll(bob, true);
        assertTrue(nft.isApprovedForAll(alice, bob));
        assertTrue(nft.clearUserData(alice));
        assertFalse(sale.whitelist(alice));
        assertEq(sale.whitelistMinted(alice), 0);
        assertFalse(nft.isApprovedForAll(alice, bob));
        nft.setSalePhase(SaleManager.SalePhase.Public);
        uint256 id = buy(alice);
        vm.prank(bob);
        vm.expectRevert();
        nft.transferFrom(alice, bob, id);
        vm.prank(alice);
        nft.setApprovalForAll(bob, true);
        vm.prank(bob);
        nft.transferFrom(alice, bob, id);
        assertEq(nft.ownerOf(id), bob);
        assertTrue(nft.clearUserData(alice));
        assertFalse(nft.isApprovedForAll(alice, bob));
    }

    function test_ClearBatchesFreezeTransfersAndPurchases() public {
        for (uint256 i = 0; i < 60; i++) buy(alice);
        for (uint256 i = 0; i < 60; i++) buy(bob);
        assertFalse(nft.clearUserData(alice));
        assertEq(nft.clearingUser(), alice);
        vm.prank(bob);
        vm.expectRevert(bytes("User cleanup in progress"));
        nft.purchaseBox();
        vm.prank(bob);
        vm.expectRevert(bytes("User cleanup in progress"));
        nft.transferFrom(bob, alice, 60);
        vm.expectRevert(bytes("Finish current cleanup first"));
        nft.clearUserData(bob);
        assertTrue(nft.clearUserData(alice));
        assertEq(nft.clearingUser(), address(0));
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 60);
        vm.prank(bob);
        nft.transferFrom(bob, alice, 60);
        assertEq(nft.ownerOf(60), alice);
    }

    function test_ClearRejectsNonOwnerAndZeroAddress() public {
        uint256 id = buy(alice);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bob)
        );
        nft.clearUserData(alice);
        assertEq(nft.ownerOf(id), alice);
        vm.expectRevert(bytes("Invalid user"));
        nft.clearUserData(address(0));
        vm.prank(bob);
        vm.expectRevert();
        sale.clearUserData(alice);
    }

    function test_ClearEmptyUserIsRepeatable() public {
        assertTrue(nft.clearUserData(alice));
        assertTrue(nft.clearUserData(alice));
        assertEq(nft.clearingUser(), address(0));
    }

    function test_ClearRequiresSaleOwnershipBeforeChangingData() public {
        uint256 id = buy(alice);
        vm.prank(address(nft));
        sale.transferOwnership(bob);
        vm.expectRevert(bytes("NFT must own SaleManager"));
        nft.clearUserData(alice);
        assertEq(nft.clearingUser(), address(0));
        assertEq(nft.ownerOf(id), alice);
    }

    function test_LateRealVRFCallbackCleansRequestWithoutRestoringNFT() public {
        address coordinator = address(0xC001);
        VRFHandler impl = new VRFHandler();
        VRFHandler realHandler = VRFHandler(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        VRFHandler.initialize,
                        (coordinator, bytes32(0), 1, 300000, 3, false)
                    )
                )
            )
        );
        nft.setVRFHandler(address(realHandler));
        vm.mockCall(
            coordinator,
            abi.encodeWithSelector(
                IVRFCoordinatorV2Plus.requestRandomWords.selector
            ),
            abi.encode(uint256(7))
        );
        uint256 id = buy(alice);
        assertEq(realHandler.getCallbackContractByRequestId(7), address(nft));
        assertTrue(nft.clearUserData(alice));
        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        vm.prank(coordinator);
        realHandler.rawFulfillRandomWords(7, words);
        assertEq(realHandler.getCallbackContractByRequestId(7), address(0));
        assertCleared(id);
    }
}
