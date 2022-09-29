import { ethers } from "hardhat";
import dotenv from "dotenv";

// Load environment variables.
dotenv.config();
const { STAKE_TOKEN, REWARD_TOKEN } = process.env;

async function main() {
  if (!STAKE_TOKEN || !REWARD_TOKEN) {
    throw new Error("Could not find STAKE_TOKEN and REWARD_TOKEN in env");
  }

  const StakingSharedPool = await ethers.getContractFactory("StakingSharedPool");
  const stakingSharedPool = await StakingSharedPool.deploy(STAKE_TOKEN, REWARD_TOKEN);

  await stakingSharedPool.deployed();

  console.log(`StakingSharedPool deployed to ${stakingSharedPool.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
