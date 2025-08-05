help: ## 显示帮助（默认目标）
	@printf "\n$(C_BOLD)用法：$(C_RST) make $(C_CYAN)<TARGET>$(C_RST) [VAR=val]\n\n"
	@awk 'BEGIN { OFS=""; } \
	/^### / { printf "\n\033[1m%s\033[0m\n", substr($$0,5); next } \
	/^[^[:space:]]+:.*##/ { \
		target=$$1; sub(/:$$/,"",target); \
		idx=index($$0,"##"); \
		desc=""; if (idx) { desc=substr($$0, idx+2) } ; \
		gsub(/^[ \t]+/,"",desc); \
		printf "  \033[36m%-30s\033[0m %s\n", target, desc; \
	}' $(MAKEFILE_LIST)
	@printf "\n$(C_DIM)提示：可用 'make test-某用例' 跑单测；用 'VAR=...' 传参（如 SEPOLIA_RPC_URL）。$(C_RST)\n"

help-%: ## 按关键字搜索目标
	@awk -v kw="$(word 2,$(MAKECMDGOALS))" 'BEGIN { OFS=""; found=0; } \
	/^[^[:space:]]+:.*##/ { \
		line=$$0; tl=tolower(line); if (index(tl, tolower(kw))) { \
			target=$$1; sub(/:$$/,"",target); \
			idx=index(line,"##"); \
			desc=""; if (idx) { desc=substr(line, idx+2) } ; \
			gsub(/^[ \t]+/,"",desc); \
			printf "  \033[36m%-30s\033[0m %s\n", target, desc; \
			found=1; \
		} \
	} \
	END { if (!found) { printf "\033[31m未找到包含关键字：%s 的目标。\033[0m\n", kw } }' $(MAKEFILE_LIST)


-include .env
export

.PHONY: all test clean build update format anvil help deploy-anvil deploy-sepolia deploy-mainnet \
        snapshot test-% deploy-pass deploy-share deploy-Luffy Mint-Luffy check-balance pk-to-address

### ========== 通用命令 ==========
all: clean install update build ## 一键清理→安装→更新→编译

clean: ## 清理构建产物
	forge clean

install: ## 安装依赖（forge-std）
	forge install foundry-rs/forge-std
	forge install OpenZeppelin/openzeppelin-contracts@v5.4.0
	forge install Cyfrin/foundry-devops

update: ## 更新依赖
	forge update

build: ## 编译项目
	forge build

### ========== 测试相关命令 ==========
test: ## 运行全部测试（详细日志）
	@echo "🧪 Running Tests..."
	forge test -vvv

snapshot: ## 生成 gas 快照
	forge snapshot

format: ## 格式化代码
	forge fmt

test-%: ## 跑单个测试用例：make test-<TestName>
	forge test --match-test $* -vvvv

### ========== 本地链 ==========
anvil: ## 启动本地 Anvil（12s出块，含助记词）
	@echo "🚀 Starting local Anvil chain..."
	anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 12

### ========== 一键部署 ==========
deploy-anvil: ## 部署到本地 Anvil
	@echo "🚀 Deploying to local Anvil..."
	@forge script script/DeployAll.s.sol:DeployAll --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) --broadcast -vvv

deploy-sepolia: ## 部署到 Sepolia（含 Etherscan 验证）
	@echo "🚀 Deploying to Sepolia..."
	@forge script script/DeployAll.s.sol:DeployAll --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvv

deploy-mainnet: ## 部署到 Mainnet（含 Etherscan 验证）
	@echo "🚀 Deploying to Mainnet..."
	@forge script script/DeployAll.s.sol:DeployAll --rpc-url $(MAINNET_RPC_URL) --private-key $(MAINNET_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvv

### ========== 单独部署 ==========
deploy-pass: ## 仅部署：KYC Pass NFT（到 Anvil）
	@echo "🚀 Deploying to local Anvil..."
	@forge script script/DeployKycPassNFT.s.sol:DeployKycPassNFT --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) --broadcast -vvv

deploy-share: ## 仅部署：Vault Token（到 Anvil）
	@echo "🚀 Deploying to local Anvil..."
	@forge script script/DeployVaultToken.s.sol:DeployVaultToken --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) --broadcast -vvv

### ========== NFT ==========
deploy-Luffy: ## 部署示例 NFT（到 Sepolia，含验证）
	@echo "🚀 Deploying to Sepolia..."
	@forge script script/DeployBasicNFT.s.sol:DeployBasicNFT --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvv

Mint-Luffy: ## 自动铸造示例 NFT（到 Sepolia）
	@echo "🚀 Mint NFT to Sepolia..."
	@forge script script/autoMintNFT.s.sol:autoMintLuffyNFT --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvv

### ========== 实用工具 ==========
check-balance: ## 查询钱包地址与 ETH 余额（Sepolia）
	@echo "🔍 Checking wallet balance..."
	@ADDRESS=$$(cast wallet address --private-key $(SEPOLIA_PRIVATE_KEY)) && \
	echo "📮 Wallet address: $$ADDRESS" && \
	echo "💰 ETH Balance: " && \
	cast balance $$ADDRESS --rpc-url $(SEPOLIA_RPC_URL)

pk-to-address: ## 用私钥推导地址（Sepolia）
	@echo "🔍 Search private key to address..."
	@echo "🔍 Your wallet address:"
	@cast wallet address --private-key $(SEPOLIA_PRIVATE_KEY)

deps-versions: ## 打印依赖版本信息
	@printf "forge-std       : " ; git -C lib/forge-std describe --tags --always --abbrev=12 2>/dev/null || echo "not installed"
	@printf "openzeppelin     : " ; git -C lib/openzeppelin-contracts describe --tags --always --abbrev=12 2>/dev/null || echo "not installed"
	@printf "foundry-devops   : " ; git -C lib/foundry-devops describe --tags --always --abbrev=12 2>/dev/null || echo "not installed"

push: ## 推送代码到远程仓库
	@echo "🔍 Pushing code to remote repository..."
	./push.sh

pull: ## 拉取代码到本地
	@echo "🔍 Pulling code from remote repository..."
	./pull.sh