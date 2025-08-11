## 项目概述

一个面向实用场景的去中心化、超额抵押、锚定美元的稳定币系统（DSC）。你可以用高质量的加密资产（如 WETH、WBTC）作为抵押，一键铸造稳定币 DSC，并在任意时刻还债或赎回抵押。系统以“风险优先”为设计原则，关注真实可用性与稳健性。

### 项目细节
- **超额抵押的极佳安全边际**：默认需要约 200% 抵押率，系统始终“先有仓、后有债”，更抗风险。
- **实时风险控制**：系统持续监控账户“健康度”（Health Factor），当风险升高时及时限制新增风险和触发清算，保护整体安全。
- **清算激励与市场化修复**：清算人可获得约 10% 的清算奖励，市场博弈帮助系统快速回归稳态。
- **一键式体验**：支持“抵押+铸造”“还债+赎回”的组合操作，一次交易完成多步操作，省心省 Gas。
- **对接主流价格源**：内置对 Chainlink 价格的集成，尽量贴近真实市场价格。
- **完善的可观测性**：关键路径全事件化，出现问题能快速定位并回溯。

### 功能清单
- 与 USD 1:1 挂钩的稳定币 DSC（ERC20，可销毁/可铸造，权限受控）
- 抵押管理（存入、赎回）与债务管理（铸造、还债）
- 风险控制（账户健康度监测、最小健康阈值）
- 清算机制（当健康度过低时，市场化清算并提供奖励）
- 原子组合操作（抵押+铸造、还债+赎回）
- 链上事件与错误处理完善

### 关键参数（默认）
- **超额抵押程度**：约 200%（即抵押价值需显著高于债务）
- **清算奖励**：约 10%
- **清算触发条件**：账户健康度低于系统最小安全值时

以上参数可根据不同网络与风险偏好做策略化配置，以适配更多业务场景。

## Quickstart

### 先决条件
- 已安装 Git、Foundry（包含 `forge` / `cast` / `anvil`）
- 建议在项目根目录准备 `.env` 以承载网络与私钥变量

### 1) 克隆仓库
```bash
git clone https://github.com/JNHFlow21/DeFi-DecentralizedStableCoin.git
cd DeFi-DecentralizedStableCoin
```

### 2) 安装依赖并编译
- 一键清理→安装→更新→编译：
```bash
make all
```
- 或分别执行：
```bash
make install
make update
make build
```

### 3) 本地网络（Anvil）部署
1. 启动本地链（建议用新终端窗口）：
```bash
make anvil
```
2. 在项目根目录创建 `.env`：
```bash
ANVIL_RPC_URL=http://127.0.0.1:8545
ANVIL_PRIVATE_KEY=0x<你的本地测试私钥>
```
3. 一键部署：
```bash
make deploy-anvil
```
说明：如本地缺少抵押资产与价格源，部署脚本会自动部署 Mock 资产与喂价，开箱即用。

### 4) 测试
- 全量测试：
```bash
make test
```
- 运行单个用例（例如 `test_liquidate_success`）：
```bash
make test-test_liquidate_success
```
- 生成 Gas 快照：
```bash
make snapshot
```
- 代码格式化：
```bash
make format
```

### 5) 部署到测试网（Sepolia）
1. 在 `.env` 配置：
```bash
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/<your-key>
SEPOLIA_PRIVATE_KEY=0x<你的私钥>
ETHERSCAN_API_KEY=<你的Etherscan API Key>
```
2. 一键部署并验证：
```bash
make deploy-sepolia
```

### 6) 主网部署（可选）
1. 在 `.env` 配置：
```bash
MAINNET_RPC_URL=https://mainnet.infura.io/v3/<your-key>
MAINNET_PRIVATE_KEY=0x<你的私钥>
ETHERSCAN_API_KEY=<你的Etherscan API Key>
```
2. 一键部署并验证：
```bash
make deploy-mainnet
```

### 7) 常用工具
- 查看帮助/全部目标：
```bash
make help
```
- 打印依赖版本：
```bash
make deps-versions
```
- 查询钱包余额（Sepolia）：
```bash
make check-balance
```
- 用私钥推导地址（Sepolia）：
```bash
make pk-to-address
```
- 检索合约自定义错误及其 selector：
```bash
make errors con=src/DSCEngine.sol:DSCEngine
make errors con=src/DSCEngine.sol:DSCEngine sig=0x<selector>
```

## 已知问题（欢迎共建）
当抵押资产价格在极短时间内大幅下跌时，可能出现“资不抵债”的极端情形，导致随后的操作报错并回退。该问题尚未投入系统性治理（例如引入更保守阈值、价格缓冲、TWAP 等方案），欢迎各位朋友讨论与提交 PR，一起把这个协议打磨得更稳健、更可用。
