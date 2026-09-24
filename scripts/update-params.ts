import { network } from "hardhat";

const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });

const NFT_PROXY = "0xf2C9b17615Df0233bd2b0B8a46591D43156dB8A7";
const SALE_PROXY = "0x4Ad562074Db620e5E4D3F77f322D5b4D7E488a23";

const PRICE = 1000000000000000n; // 0.001 ETH
const MAX_PER_WALLET = 1000n;
const MAX_SUPPLY = 100000n;

// 1. 部署新 NFT 实现（含 setMaxSupply）
const newImpl = await ethers.deployContract("NFTBlindBoxUpgradeable");
await newImpl.waitForDeployment();
console.log("new NFT impl     :", await newImpl.getAddress());

// 2. UUPS 就地升级（代理地址不变）
const nft = await ethers.getContractAt("NFTBlindBoxUpgradeable", NFT_PROXY);
const upTx = await nft.upgradeToAndCall(await newImpl.getAddress(), "0x");
await upTx.wait();
console.log("NFT upgraded, proxy:", NFT_PROXY);

// 3. setMaxSupply
await (await nft.setMaxSupply(MAX_SUPPLY)).wait();
console.log("maxSupply        :", MAX_SUPPLY.toString());

// 4. SaleManager setPrice + setMaxPerWallet
const sale = await ethers.getContractAt("SaleManager", SALE_PROXY);
await (await sale.setPrice(PRICE)).wait();
await (await sale.setMaxPerWallet(MAX_PER_WALLET)).wait();
console.log("price            :", PRICE.toString());
console.log("maxPerWallet     :", MAX_PER_WALLET.toString());

console.log("\n=== DONE ===");
