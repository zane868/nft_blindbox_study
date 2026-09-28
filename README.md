# Sample Hardhat 3 Project (`mocha` and `ethers`)

This project showcases a Hardhat 3 project using `mocha` for tests and the `ethers` library for Ethereum interactions.

To learn more about Hardhat 3, please visit the [Getting Started guide](https://hardhat.org/docs/getting-started#getting-started-with-hardhat-3). To share your feedback, join our [Hardhat 3](https://hardhat.org/hardhat3-telegram-group) Telegram group or [open an issue](https://github.com/NomicFoundation/hardhat/issues/new) in our GitHub issue tracker.

## Project Overview

This example project includes:

- A simple Hardhat configuration file.
- Foundry-compatible Solidity unit tests.
- TypeScript integration tests using `mocha` and ethers.js
- Examples demonstrating how to connect to different types of networks, including locally simulating OP mainnet.

## Usage

### Running Tests

To run all the tests in the project, execute the following command:

```shell
npx hardhat test
```

You can also selectively run the Solidity or `mocha` tests:

```shell
npx hardhat test solidity
npx hardhat test mocha
```

### Make a deployment to Sepolia

This project includes an example Ignition module to deploy the contract. You can deploy this module to a locally simulated chain or to Sepolia.

To run the deployment to a local chain:

```shell
npx hardhat ignition deploy ignition/modules/Counter.ts
```

To run the deployment to Sepolia, you need an account with funds to send the transaction. The provided Hardhat configuration includes a Configuration Variable called `SEPOLIA_PRIVATE_KEY`, which you can use to set the private key of the account you want to use.

You can set the `SEPOLIA_PRIVATE_KEY` variable using the `hardhat-keystore` plugin or by setting it as an environment variable.

To set the `SEPOLIA_PRIVATE_KEY` config variable using `hardhat-keystore`:

```shell
npx hardhat keystore set SEPOLIA_PRIVATE_KEY
```

After setting the variable, you can run the deployment with the Sepolia network:

```shell
npx hardhat ignition deploy --network sepolia ignition/modules/Counter.ts
```

### 清空指定用户数据

NFT owner 调用 `clearUserData(address user)`。每次最多处理 100 条购买记录/历史 tokenId，重复调用同一用户，直到 `clearingUser()` 返回零地址并发出 `UserDataCleared`。大量 NFT 需要多笔交易；交易返回值无法直接从 receipt 读取，应通过状态或事件判断完成。

清理范围：

- 销毁用户购买的 NFT（包括已转给其他人的），以及该用户当前持有的其他 NFT。
- 删除这些 NFT 的稀有度、盲盒状态、单币授权、URI 覆盖值和买家记录。
- 清空该用户的购买历史、保底轮次、白名单资格和白名单购买次数。
- 使用户已有的全部 operator 授权失效；以后仍可重新授权。

分批清理期间暂停整个 NFT 合约的购买和转账，避免扫描期间转移 NFT 漏清。清理完成后恢复。其他用户的历史购买列表可能仍包含已销毁 NFT 的编号，查询所有权时这些编号会回滚。

部署前提：NFT 与 SaleManager 都需升级到含清理逻辑的实现；SaleManager 的 owner 必须是 NFT 代理地址（项目已有 `scripts/fix-sale-owner.ts` 展示该关系）。未满足此条件时清理会回滚。

`totalSupply` 在本项目兼作累计铸造数和下一个 tokenId，清理不减少它，避免旧 VRF 请求作用于复用的编号。因此销毁不恢复总铸造额度。已发出的 VRF 请求不能从 Chainlink 网络撤销；其迟到回调会被 NFT 忽略，VRFHandler 随后正常清理请求记录。失败且不会再返回的旧请求不在这个按用户清理方法中删除。

链上历史交易、事件和区块浏览器索引不能删除。合约保留必要的已清理 token 标记及授权版本，用于防止旧回调/旧授权重新生效。该方法不退款，也不清空合约资金、全局配置或其他用户的业务记录。

默认和 production 编译均开启 optimizer（200 runs），部署应使用优化后的产物。
