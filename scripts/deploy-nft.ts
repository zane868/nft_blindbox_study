import { network } from "hardhat";

const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });

const [deployer] = await ethers.getSigners();

// ============ 部署参数 ============
const NAME = "BlindBox";
const SYMBOL = "BBOX";
const MAX_SUPPLY = 100000n;
const BASE_URI = "https://example.com/metadata/"; // TODO 替换为真实元数据 URI
const VERSION = 1n;
const PRICE = 1000000000000000n; // 0.001 ETH
const MAX_PER_WALLET = 1000n;
const VRF_HANDLER = "0xd7625dD6C905315b48936c8109939BF11E1B7a6c";

// ============ 1. SaleManager ============
const saleImpl = await ethers.deployContract("SaleManager");
await saleImpl.waitForDeployment();
console.log("SaleManager impl  :", await saleImpl.getAddress());

const saleInitData = saleImpl.interface.encodeFunctionData("initialize", [
  PRICE,
  MAX_PER_WALLET,
]);
const saleProxy = await ethers.deployContract("TransparentProxy", [
  await saleImpl.getAddress(),
  deployer.address,
  saleInitData,
]);
await saleProxy.waitForDeployment();
const saleProxyAddr = await saleProxy.getAddress();
console.log("SaleManager proxy :", saleProxyAddr);

// ============ 2. NFTBlindBox ============
const nftImpl = await ethers.deployContract("NFTBlindBoxUpgradeable");
await nftImpl.waitForDeployment();
console.log("NFTBlindBox impl  :", await nftImpl.getAddress());

const nftInitData = nftImpl.interface.encodeFunctionData("initialize", [
  NAME,
  SYMBOL,
  MAX_SUPPLY,
  saleProxyAddr,
  VRF_HANDLER,
  BASE_URI,
  VERSION,
]);
const nftProxy = await ethers.deployContract("UUPSProxy", [
  await nftImpl.getAddress(),
  nftInitData,
]);
await nftProxy.waitForDeployment();
const nftProxyAddr = await nftProxy.getAddress();
console.log("NFTBlindBox proxy :", nftProxyAddr);

console.log("\n=== DONE ===");
