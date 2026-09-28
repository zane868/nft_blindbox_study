import { network } from "hardhat";

const { ethers } = await network.create({ network: "sepolia", chainType: "l1" });

// 固定 SaleManager 代理地址
const SALE_PROXY = "0x4Ad562074Db620e5E4D3F77f322D5b4D7E488a23";

// EIP-1967 implementation 槽位
const IMPL_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

// 透明代理构造函数里第一个 `new ProxyAdmin(initialOwner)`，CREATE nonce = 1
const proxyAdmin = ethers.getCreateAddress({ from: SALE_PROXY, nonce: 1 });
console.log("ProxyAdmin:", proxyAdmin);

// 1. 部署新实现
const impl = await ethers.deployContract("SaleManager");
await impl.waitForDeployment();
const implAddr = await impl.getAddress();
console.log("new SaleManager impl:", implAddr);

// 2. 就地升级（代理地址不变）
const admin = await ethers.getContractAt(
  ["function upgradeAndCall(address proxy, address newImplementation, bytes data)"],
  proxyAdmin,
);
const tx = await admin.upgradeAndCall(SALE_PROXY, implAddr, "0x");
await tx.wait();
console.log("upgraded, proxy unchanged:", SALE_PROXY);

// 3. 验证实现槽位
const stored = "0x" + (await ethers.provider.getStorage(SALE_PROXY, IMPL_SLOT)).slice(-40);
console.log("proxy now points to:", stored);
console.log("match:", stored.toLowerCase() === implAddr.toLowerCase());
