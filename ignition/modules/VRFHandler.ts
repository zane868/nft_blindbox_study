import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Chainlink VRF v2.5 (V2Plus) — Sepolia
const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
const KEY_HASH =
  "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae";
const SUBSCRIPTION_ID =
  90541054269866130233144184856202276681800967200364691296980408313294816901598n;
const CALLBACK_GAS_LIMIT = 150000;
const REQUEST_CONFIRMATIONS = 3;
const NATIVE_PAYMENT = false; // LINK 支付

export default buildModule("VRFHandlerModule", (m) => {
  // 1. 部署实现合约
  const vrfHandlerImpl = m.contract("VRFHandler");

  // 2. 编码 initialize 调用
  const initData = m.encodeFunctionCall(vrfHandlerImpl, "initialize", [
    VRF_COORDINATOR,
    KEY_HASH,
    SUBSCRIPTION_ID,
    CALLBACK_GAS_LIMIT,
    REQUEST_CONFIRMATIONS,
    NATIVE_PAYMENT,
  ]);

  // 3. 部署透明代理（initialOwner 为部署账户）
  const vrfHandlerProxy = m.contract("VRFHandlerProxy", [
    vrfHandlerImpl,
    m.getAccount(0),
    initData,
  ]);

  return { vrfHandlerImpl, vrfHandlerProxy };
});
