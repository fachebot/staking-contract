
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import type { ERC20Token } from "../typechain-types/contracts/test/ERC20Token";
import type { StakingWithSharedPool } from "../typechain-types/contracts/StakingWithSharedPool";

describe("StakingWithSharedPool", function () {
    let stakeToken: ERC20Token;
    let rewardToken: ERC20Token;
    let signers: SignerWithAddress[] = [];
    let stakingContract: StakingWithSharedPool;

    beforeEach(async function () {
        signers = await ethers.getSigners();

        const ERC20 = await ethers.getContractFactory("ERC20Token");
        stakeToken = await ERC20.deploy("Stake Token", "STAKE", "1000000000000000000000");
        rewardToken = await ERC20.deploy("Reward Token", "REWARD", "1000000000000000000000");

        const StakingContract = await ethers.getContractFactory("StakingWithSharedPool");
        stakingContract = await StakingContract.deploy(stakeToken.address, rewardToken.address);
    });

    describe("New Round", function () {
        it("Should revert with the right error if insufficient allowance", async function () {
            const StakingContract = await ethers.getContractFactory("StakingWithSharedPool");
            await StakingContract.deploy(stakeToken.address, rewardToken.address, 100000, 100, 10);
        });

        it("Should revert with the right error if the endBlock LE to startBlock", async function () {
            const StakingContract = await ethers.getContractFactory("StakingWithSharedPool");
            await StakingContract.deploy(stakeToken.address, rewardToken.address, 100000, 100, 10);
        });
    })
});
