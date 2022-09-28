
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import type { ERC20Token } from "../typechain-types/contracts/test/ERC20Token";
import type { StakingSharedPool } from "../typechain-types/contracts/StakingSharedPool";

describe("StakingSharedPool", function () {
    let startBlock: number;
    let stakeToken: ERC20Token;
    let rewardToken: ERC20Token;
    let owner: SignerWithAddress;
    let signers: SignerWithAddress[] = [];
    let stakingContract: StakingSharedPool;
    const tokenPerBlock = BigNumber.from("10000000000000000000");

    before(async function () {
        signers = await ethers.getSigners();
        owner = signers[0];

        const ERC20 = await ethers.getContractFactory("ERC20Token");
        stakeToken = await ERC20.deploy("Stake Token", "STAKE", "1000000000000000000000");
        rewardToken = await ERC20.deploy("Reward Token", "REWARD", "1000000000000000000000");

        const StakingContract = await ethers.getContractFactory("StakingSharedPool");
        stakingContract = await StakingContract.deploy(stakeToken.address, rewardToken.address);
        console.info("stakingContract:", stakingContract.address);
    });

    describe("New Round", function () {
        it("Should revert with the right error if insufficient allowance", async function () {
            await expect(
                stakingContract.newRound(1, 20, "1000000000000000000000")
            ).to.be.revertedWith("ERC20: insufficient allowance");
        });

        it("Should revert with the right error if the endBlock LE to startBlock", async function () {
            await rewardToken.approve(stakingContract.address, "1000000000000000000000");
            await expect(
                stakingContract.newRound(20, 1, "1000000000000000000000")
            ).to.be.revertedWith("StakingSharedPool: invalid block range");
        });

        it("Should set the right round", async function () {
            await rewardToken.approve(stakingContract.address, "1000000000000000000000");
            await stakingContract.newRound(1, 20, tokenPerBlock);
        });
    })

    describe("Deposit", function () {
        it("Should revert with the right error if insufficient allowance", async function () {
            await expect(
                stakingContract.deposit("1000", owner.address)
            ).to.be.revertedWith("ERC20: insufficient allowance");
        });

        it("Should set the right deposit amount", async function () {
            await stakeToken.approve(stakingContract.address, "1000");
            const tx = await stakingContract.deposit("1000", owner.address);
            startBlock = tx.blockNumber as number;
        });
    })

    describe("Stake Reward", function () {
        it("Should receive the right reward amount", async function () {
            const times = 3;
            for (let i = 0; i < times; i++) {
                await ethers.provider.send("evm_mine", []);
                const reward = await stakingContract.pendingReward(owner.address);
                expect(reward.eq(tokenPerBlock.mul(i + 1)));
            }

            let lastStaker1Reward: BigNumber;
            stakeToken.transfer(signers[1].address, "1000");
            stakeToken.transfer(signers[2].address, "1000");
            await stakeToken.connect(signers[1]).approve(stakingContract.address, "1000");
            const tx = await stakingContract.connect(signers[1]).deposit("1000", signers[1].address);
            {
                const reward = await stakingContract.pendingReward(owner.address);
                expect(reward.eq(tokenPerBlock.mul(tx.blockNumber as number - startBlock)));
                lastStaker1Reward = reward;
            }
            
            await stakeToken.connect(signers[2]).approve(stakingContract.address, "1000");
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                expect(staker2reward.eq(tokenPerBlock.div(2)));
                expect(staker1reward.eq(lastStaker1Reward.add(tokenPerBlock.div(2))));
            }

            await stakingContract.connect(signers[2]).deposit("1000", signers[2].address);
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq(BigNumber.from(0)));
                expect(staker2reward.eq(tokenPerBlock.div(2).mul(2)));
                expect(staker1reward.eq(lastStaker1Reward.add(tokenPerBlock.div(2).mul(2))));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const value = tokenPerBlock.div(3);
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq(value));
                expect(staker2reward.eq(tokenPerBlock.div(2).mul(2).add(value)));
                expect(staker1reward.eq(lastStaker1Reward.add(tokenPerBlock.div(2).mul(2)).add(value)));
            }
        });

        it("Should receive the right reward amount after re deposit", async function () {
            await stakeToken.approve(stakingContract.address, "1000");
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("6666666666666666666"));
                expect(staker2reward.eq("16666666666666666666"));
                expect(staker1reward.eq("86666666666666666666"));
            }

            await stakingContract.deposit("1000", owner.address);
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("90000000000000000000"));
                expect(staker2reward.eq("20000000000000000000"));
                expect(staker1reward.eq("10000000000000000000"));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("95000000000000000000"));
                expect(staker2reward.eq("22500000000000000000"));
                expect(staker1reward.eq("12500000000000000000"));
            }
        });

        it("Should receive the right reward amount after withdraw", async function () {
            const oldBalance = await stakeToken.balanceOf(owner.address);
            await stakingContract.withdraw("1000", owner.address);
            const newBalance = await stakeToken.balanceOf(owner.address);
            expect(newBalance.eq(oldBalance.add("1000")));

            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("100000000000000000000"));
                expect(staker2reward.eq("25000000000000000000"));
                expect(staker1reward.eq("15000000000000000000"));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("103333333333333333333"));
                expect(staker2reward.eq("28333333333333333333"));
                expect(staker1reward.eq("18333333333333333333"));
            }
        });

        it("Should receive the right reward amount after harvest", async function () {
            const oldBalance = await rewardToken.balanceOf(owner.address);
            await stakingContract.harvest(owner.address);
            const newBalance = await rewardToken.balanceOf(owner.address);
            expect(newBalance.eq(oldBalance.add("10666666666666666666")));

            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("21666666666666666666"));
                expect(staker2reward.eq("31666666666666666666"));
                expect(staker1reward.eq("0"));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("24999999999999999999"));
                expect(staker2reward.eq("34999999999999999999"));
                expect(staker1reward.eq("3333333333333333333"));
            }
        });

        it("Should receive the right reward amount after withdraw harvest", async function () {
            const oldStakeBalance = await stakeToken.balanceOf(owner.address);
            const oldRewardBalance = await rewardToken.balanceOf(owner.address);
            await stakingContract.withdrawAndHarvest("1000", owner.address);
            const newStakeBalance = await stakeToken.balanceOf(owner.address);
            const newRewardBalance = await rewardToken.balanceOf(owner.address);
            expect(newStakeBalance.eq(oldStakeBalance.add("1000")));
            expect(newRewardBalance.eq(oldRewardBalance.add("6666666666666666666")));

            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("28333333333333333333"));
                expect(staker2reward.eq("38333333333333333333"));
                expect(staker1reward.eq("0"));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(owner.address);
                const staker2reward = await stakingContract.pendingReward(signers[1].address);
                const staker3reward = await stakingContract.pendingReward(signers[2].address);
                expect(staker3reward.eq("33333333333333333333"));
                expect(staker2reward.eq("43333333333333333333"));
                expect(staker1reward.eq("0"));
            }
        });
    })
});
