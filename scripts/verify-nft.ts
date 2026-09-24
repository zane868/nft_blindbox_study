import { network } from "hardhat";
const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });

const NFT = "0xf2C9b17615Df0233bd2b0B8a46591D43156dB8A7";
const SALE = "0x4Ad562074Db620e5E4D3F77f322D5b4D7E488a23";

const nft = await ethers.getContractAt("NFTBlindBoxUpgradeable", NFT);
console.log("NFT name     :", await nft.name());
console.log("NFT symbol   :", await nft.symbol());
console.log("NFT maxSupply:", (await nft.maxSupply()).toString());
console.log("NFT saleMgr  :", await nft.saleManager());
console.log("NFT vrfHndlr :", await nft.vrfHandler());
console.log("NFT version  :", (await nft.getVersion()).toString());
console.log("NFT owner    :", await nft.owner());

const sale = await ethers.getContractAt("SaleManager", SALE);
console.log("Sale price      :", (await sale.price()).toString());
console.log("Sale maxPerW    :", (await sale.maxPerWallet()).toString());
console.log("Sale phase      :", (await sale.currentPhase()).toString());
console.log("Sale active     :", await sale.saleActive());
