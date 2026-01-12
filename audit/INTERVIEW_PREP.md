# INTERVIEW PREP (Bybit 审计岗)

## Project Walkthrough
- **抵押（Collateral）**：用户通过 `depositCollateral` 或组合入口 `depositCollateralAndMintDsc` 存入抵押品；系统记录抵押数量，并通过 Chainlink 预言机估算 USD 价值。
- **铸造（Mint）**：`mintDsc` 或组合入口会增加用户债务（DSC 铸币量），随后通过健康因子（Health Factor）校验是否满足最小安全阈值。
- **健康因子（HF）**：`HF = (collateralValue * liquidationThreshold / liquidationPrecision) * 1e18 / debt`，低于 1e18 时可被清算。
- **清算（Liquidation）**：当用户 HF < 1e18，清算人用 DSC 覆盖债务，获取等值抵押品 + 奖励（10%）。清算后需确保被清算人 HF 改善。
- **稳定币合约**：`DecentralizedStableCoin` 仅允许引擎合约铸币与销毁，避免外部任意增发。

## Bug Deep Dive

### 漏洞 1：Oracle 数据未校验有效性
**原理解析：**
`PriceConverter.getPrice` 直接使用 `latestRoundData` 的 `answer`，没有检查是否为正数、是否为过期轮次或未完成轮次。一旦喂价出现异常或过期，抵押估值会失真，可能允许超额铸币或阻断清算。

**修复思路：**
增加 `price > 0`、`updatedAt != 0`、`answeredInRound >= roundId` 校验，异常直接 revert。

**面试官问答脚本：**
- Q：你如何判断该项目的预言机使用是否安全？
- A：我重点看了 `PriceConverter.getPrice`，发现直接用 `latestRoundData` 的 `answer`，没有校验 `updatedAt` 和 `answeredInRound`。这意味着异常轮次或过期数据会被直接用于估值，进而影响铸币上限和清算条件。
- Q：你做了哪些修复？
- A：我在 `getPrice` 中增加了三项校验：价格必须大于 0、`updatedAt` 不能为 0、`answeredInRound` 必须 >= `roundId`。这些是 Chainlink 推荐的安全检查，可以防止读取到无效价格。

### 漏洞 2：抵押品与喂价精度未归一化
**原理解析：**
引擎默认所有抵押品是 18 位精度、喂价是 8 位精度。当 token 或喂价 decimals 不一致时，抵押估值会偏移。例如 WBTC 8 位精度会被严重低估，导致用户无法合理铸币或误触发清算。

**修复思路：**
在 `PriceConverter` 中按 `Aggregator.decimals()` 统一价格为 1e18；在 `DSCEngine` 中引入 token 数量的 1e18 归一化/反归一化函数，避免估值偏差。

**面试官问答脚本：**
- Q：你如何发现精度问题的？
- A：我注意到代码里写了“抵押物精度都是 1e18”，但项目又提到 WBTC。WBTC 实际是 8 位精度，这意味着当前估值逻辑会低估 1e10 倍，属于明显的业务逻辑风险。
- Q：你如何修复？
- A：我在引擎里加入了基于 `IERC20Metadata.decimals()` 的数量归一化，并在价格层统一使用预言机 decimals 缩放到 1e18，确保任何 token/喂价精度组合都能正确估值。
