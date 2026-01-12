# Audit Report

## Executive Summary
- 审计范围：`src/DSCEngine.sol`、`src/DecentralizedStableCoin.sol`、`src/_library/PriceConverter.sol` 及部署脚本中的配置假设（只读参考）。
- 漏洞统计：Critical 0 / High 0 / Medium 2 / Low 0 / Informational 0。

## Detailed Findings

### 1) Oracle 数据未校验有效性（Medium）
**Description:**
`PriceConverter.getPrice` 直接使用 `latestRoundData()` 的价格，未校验 `price` 是否为正、`updatedAt` 是否为 0、`answeredInRound` 是否落后于 `roundId`。在喂价异常或未完成轮次时，可能读取到 0/负数/过期数据，导致抵押品估值错误，进而影响铸币上限与清算判断。

**Location:**
- `src/_library/PriceConverter.sol:20`

**Remediation:**
- 在 `getPrice` 中增加 `price > 0`、`updatedAt != 0`、`answeredInRound >= roundId` 校验，异常时直接 revert。

### 2) 抵押品与喂价精度未归一化（Medium）
**Description:**
抵押品估值默认将 token 数量视为 18 位、喂价默认 8 位精度。当抵押 token 或喂价 decimals 不符合该假设时，估值会出现偏差：
- token decimals < 18（如 WBTC 8 位）会被显著低估，导致用户无法正常铸币或频繁触发清算（DoS 类风险）。
- token/喂价 decimals > 18 或与假设不一致时，可能造成估值偏高，带来潜在的超额铸币风险。

**Location:**
- `src/DSCEngine.sol:452`
- `src/DSCEngine.sol:460`
- `src/_library/PriceConverter.sol:40`
- `src/_library/PriceConverter.sol:54`

**Remediation:**
- 在 `PriceConverter` 内部按 `Aggregator.decimals()` 将价格统一缩放到 1e18。
- 在 `DSCEngine` 内部新增 token 数量的 1e18 归一化/反归一化逻辑，以兼容不同 token decimals。

## Tool Analysis
- 静态分析：使用 Slither（报告保存在 `audit/slither-report.txt`）。
- 人工审计：围绕抵押/铸币/清算流程与预言机精度假设进行逐行审查，并结合测试用例与部署脚本对配置假设进行交叉验证。
