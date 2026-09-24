import { network } from "hardhat";

const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });

// 固定 NFTBlindBox 代理地址
const NFT_PROXY = "0xf2C9b17615Df0233bd2b0B8a46591D43156dB8A7";

// EIP-1967 implementation 槽位
const IMPL_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

// 1. 部署新实现
const impl = await ethers.deployContract("NFTBlindBoxUpgradeable");
await impl.waitForDeployment();
const implAddr = await impl.getAddress();
console.log("new NFT impl:", implAddr);

// 2. UUPS 就地升级（代理地址不变）
const nft = await ethers.getContractAt("NFTBlindBoxUpgradeable", NFT_PROXY);
const tx = await nft.upgradeToAndCall(implAddr, "0x");
await tx.wait();
console.log("upgraded, proxy unchanged:", NFT_PROXY);

// 3. 验证实现槽位
const stored = "0x" + (await ethers.provider.getStorage(NFT_PROXY, IMPL_SLOT)).slice(-40);
console.log("proxy now points to:", stored);
console.log("match:", stored.toLowerCase() === implAddr.toLowerCase());
