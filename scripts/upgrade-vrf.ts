import { network } from "hardhat";

const { ethers } = await network.create({
  network: "sepolia",
  chainType: "l1",
});

// 固定代理地址（v4，之后不再变）
const PROXY = "0xd7625dD6C905315b48936c8109939BF11E1B7a6c";
// 该代理的 ProxyAdmin（构造函数里第一个 `new ProxyAdmin(initialOwner)`，CREATE nonce=1）
const PROXY_ADMIN = "0x6e9C9d4D02A8905068bC105e35641E0D4Dd53587";

// EIP-1967 implementation 槽位
const IMPL_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

// 1. 部署新的实现合约
const impl = await ethers.deployContract("VRFHandler");
await impl.waitForDeployment();
const implAddr = await impl.getAddress();
console.log("new implementation:", implAddr);

// 2. 就地升级（代理地址不变，仅替换实现）
const admin = await ethers.getContractAt(
  ["function upgradeAndCall(address proxy, address newImplementation, bytes data)"],
  PROXY_ADMIN,
);
const tx = await admin.upgradeAndCall(PROXY, implAddr, "0x");
await tx.wait();
console.log("upgraded, proxy unchanged:", PROXY);

// 3. 验证：读取 implementation 槽位，确认代理已指向新实现
const stored = "0x" + (await ethers.provider.getStorage(PROXY, IMPL_SLOT)).slice(-40);
console.log("proxy now points to   :", stored);
console.log("match:", stored.toLowerCase() === implAddr.toLowerCase());
