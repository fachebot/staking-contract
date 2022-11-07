.PHONY: test

all: test

test:
	@npx hardhat test

flat:
	@mkdir -p dist
	@npx hardhat flatten contracts/StakingSharedPool.sol > dist/StakingSharedPool.sol
	@npx hardhat flatten contracts/StakingSharedPoolL2.sol > dist/StakingSharedPoolL2.sol