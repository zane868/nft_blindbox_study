import { network } from "hardhat";
const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });

const SALE = "0x4Ad562074Db620e5E4D3F77f322D5b4D7E488a23";
const NFT = "0xf2C9b17615Df0233bd2b0B8a46591D43156dB8A7";

const sale = await ethers.getContractAt("SaleManager", SALE);
console.log("SaleManager 当前 owner:", await sale.owner());

const tx = await sale.transferOwnership(NFT);
await tx.wait();
console.log("SaleManager 新 owner  :", await sale.owner());
console.log("=== DONE ===");
