import { network } from "hardhat";
const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });
const nft = await ethers.getContractAt("NFTBlindBoxUpgradeable", "0xf2C9b17615Df0233bd2b0B8a46591D43156dB8A7");

const tx = await nft.setSalePhase(2); // Public
await tx.wait();
console.log("setSalePhase(2) 成功 ✅");

const info = await nft.getSaleInfo();
console.log("active:", info.active, "| phase:", info.phase.toString(), "| price:", info.currentPrice.toString(), "| maxPerWallet:", info.maxWallet.toString());
