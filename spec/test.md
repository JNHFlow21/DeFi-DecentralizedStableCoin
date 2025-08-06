以下是一份针对你提供的合约和脚本的测试文档提纲，列出了每个功能点和应验证的测试场景。你只需按照下面的思路补充具体的测试用例描述即可，不需要实际代码。

⸻

一、测试环境准备
	1.	部署两个 ERC20Mock（比如 WETHMock、WBTCMock），并设置初始余额与 allowance。
	2.	部署 DecentralizedStableCoin，持有者为测试脚本中的指定地址。
	3.	部署 DSCEngine：
	•	使用初始化好的 token 地址数组和 priceFeed 地址数组；
	•	按需模拟 priceFeed 返回固定汇率；
	4.	准备若干模拟账户（Alice、Bob、Liquidator），并给与初始 token 和 DSC 余额。

⸻

二、DecentralizedStableCoin 合约测试

1. 构造函数
	•	名称与符号：name() 返回 "DecentralizedStableCoin"，symbol() 返回 "DSC"；
	•	初始 owner：合约 owner() 应为部署者地址。

2. burn(uint256 amount)
	•	正常路径：owner 持有 DSC ≥ amount 时，调用 burn(amount)，余额减少，Transfer 事件（from→0x0）和 DscBurned（若有扩展）被触发。
	•	错误路径：
	•	amount == 0 → revert DecentralizedStableCoin__AmountMustBeGreaterThanZero；
	•	amount > balanceOf(owner) → revert DecentralizedStableCoin__BurnAmountExceedsBalance；
	•	非 owner 调用 → revert（Ownable: caller is not the owner）。

3. mint(address to, uint256 amount)
	•	正常路径：owner 调用，to 的 DSC 余额增加，Transfer 事件（0x0→to）触发，返回 true。
	•	错误路径：
	•	amount == 0 → revert DecentralizedStableCoin__AmountMustBeGreaterThanZero；
	•	非 owner 调用 → revert（Ownable: caller is not the owner）。

⸻

三、DSCEngine 合约测试

1. 构造函数
	•	长度不匹配：token 数组与 priceFeed 数组长度不等时，revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch。
	•	正常初始化：映射 s_collateralTokenToPriceFeed 和列表 s_collateralTokens 正确填充。

2. receive() / fallback()
	•	向合约发送原生 ETH，应均 revert（空字符串）。

3. depositCollateralAndMintDsc(...)
	•	参数校验：
	•	amountCollateral == 0 或 amountDscToMint == 0 → revert DSCEngine__NeedsMoreThanZero；
	•	tokenCollateralAddress 未被允许 → revert DSCEngine__TokenNotAllowed。
	•	正常路径：
	1.	ERC20 transferFrom 成功，CollateralDeposited 事件触发；
	2.	内部 _mintDsc：先检查健康因子，再调用 DSC 合约 mint，触发 DscMinted 事件；
	3.	用户抵押和债务记录更新；
	•	健康因子检查：若 mint 后健康因子 < MIN → revert DSCEngine__BreaksHealthFactor。

4. redeemCollateralForDsc(...)
	•	参数校验：与 deposit 同理。
	•	正常路径：
	1.	调用 _burnDsc，触发 DscBurned；
	2.	调用 _redeemCollateral，触发 CollateralRedeemed；
	3.	健康因子校验，不合格时 revert。

5. redeemCollateral(...)
	•	仅赎回：不改变债务，只执行 _redeemCollateral，触发 CollateralRedeemed 并做 HF 校验。

6. burnDsc(uint256 amount)
	•	仅还债：执行 _burnDsc，触发 DscBurned，并 HF 校验。

7. depositCollateral(address token, uint256 amount)
	•	仅抵押：执行 _depositCollateral，触发 CollateralDeposited。

8. mintDsc(uint256 amountDscToMint)
	•	同 depositCollateralAndMintDsc 的 mint 部分。

9. liquidate(address collateral, address user, uint256 debtToCover)
	•	参数校验：
	•	debtToCover == 0 → revert DSCEngine__NeedsMoreThanZero；
	•	token 未允许 → revert DSCEngine__TokenNotAllowed；
	•	健康因子：
	•	user HF ≥ MIN → revert DSCEngine__HealthFactorOk；
	•	清算后若 user HF 未改善 → revert DSCEngine__HealthFactorNotImproved；
	•	正常路径：
	1.	计算 tokenAmountFromDebtCovered 和 bonusCollateral；
	2.	执行 _redeemCollateral 给清算者，触发 CollateralRedeemed；
	3.	执行 _burnDsc，触发 DscBurned；
	4.	触发 LiquidationPerformed 事件；
	•	重入保护：多次调用 liquidate 应受 nonReentrant 保护。

10. 纯函数 & 视图函数
	•	_calculateHealthFactor / calculateHealthFactor：
	•	totalDscMinted == 0 → 返回 type(uint256).max；
	•	其他情况，按公式 (collateralValue * threshold / precision) * PRECISION / totalDscMinted。
	•	getAccountCollateralValue：多种抵押物组合下返回正确 USD 值总和。
	•	_getUsdValue / getUsdValue、_getTokenAmountFromUsd：根据模拟 priceFeed 汇率验证计算正确。

⸻

四、DeployDSCEngine 脚本测试
	1.	initTokenAddressesAndPriceFeed：私有方法，保证 s_tokenAddresses 与 s_priceFeedAddresses 如预期；
	2.	run()：在广播模式下执行，无 revert；返回的 DecentralizedStableCoin 和 DSCEngine 地址非零且相互关联。

⸻

五、集成与边界场景
	•	多轮抵押→铸币→赎回→还债，余额与 HF 始终符合预期。
	•	抵押不同 token 组合，计算总价值。
	•	极端值测试：抵押量或债务量极大，保证无溢出；
	•	重复抵押与多账户交互；
	•	非 owner 及非注册 token 的调用均被拒绝。

⸻

六、事件校验

对每条 emit 的事件均应捕获并验证其参数正确性：
	•	CollateralDeposited、CollateralRedeemed
	•	DscMinted、DscBurned
	•	LiquidationPerformed

⸻

按此提纲填充具体场景和预期结果，即可构成一份全面的测试文档。