
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import type { ERC20Token } from "../typechain-types/contracts/test/ERC20Token";
import type { StakingSharedPoolL2 } from "../typechain-types/contracts/StakingSharedPoolL2";

describe("StakingSharedPoolL2", function () {
    let startBlock: number;
    let stakeToken: ERC20Token;
    let stakeToken2: ERC20Token;
    let rewardToken: ERC20Token;
    let owner: SignerWithAddress;
    let signers: SignerWithAddress[] = [];
    let stakingContract: StakingSharedPoolL2;
    const tokenPerBlock = BigNumber.from("10000000000000000000");

    before(async function () {
        signers = await ethers.getSigners();
        owner = signers[0];
        startBlock = await ethers.provider.getBlockNumber();

        const ERC20 = await ethers.getContractFactory("ERC20Token");
        stakeToken = await ERC20.deploy("Stake Token", "STAKE", "10000000000000000000000"); // blocknumber 1
        rewardToken = await ERC20.deploy("Reward Token", "REWARD", "10000000000000000000000"); // blocknumber 2

        const StakingContract = await ethers.getContractFactory("StakingSharedPoolL2");
        stakingContract = await StakingContract.deploy(rewardToken.address); // blocknumber 3

        await stakingContract.add(100, stakeToken.address); // blocknumber 4
    });

    describe("New Period", function () {
        it("Should revert with the right error if insufficient allowance", async function () {
            await expect(
                stakingContract.addPeriod(startBlock + 1, startBlock + 101, "1000000000000000000000") // blocknumber 5
            ).to.be.revertedWith("ERC20: insufficient allowance");
        });

        it("Should revert with the right error if the endBlock LE to startBlock", async function () {
            await rewardToken.approve(stakingContract.address, tokenPerBlock.mul(100)); // blocknumber 6
            await expect(
                stakingContract.addPeriod(startBlock + 101, startBlock + 1, "1000000000000000000000") // blocknumber 7
            ).to.be.revertedWith("StakingSharedPoolL2: invalid block range");
        });

        it("Should set the right period", async function () {
            await rewardToken.approve(stakingContract.address, tokenPerBlock.mul(100)); // blocknumber 8
            await stakingContract.addPeriod(startBlock + 12, startBlock + 112, tokenPerBlock); // blocknumber 9

            const balance = await rewardToken.balanceOf(stakingContract.address);
            expect(balance).to.equals(tokenPerBlock.mul(100));
        });
    })

    describe("Stake Token", function () {
        it("Should revert with the right error if insufficient allowance", async function () {
            await expect(
                stakingContract.stake(0, "1000", owner.address) // blocknumber 10
            ).to.be.revertedWith("ERC20: insufficient allowance");
        });

        it("Should set the right stake amount", async function () {
            await stakeToken.approve(stakingContract.address, "1000"); // blocknumber 11
            const tx = await stakingContract.stake(0, "1000", owner.address); // blocknumber 12
            expect(tx.blockNumber as number).to.equal(startBlock + 12);
        });
    })

    describe("Stake Reward", function () {
        it("Should receive the right reward", async function () {
            const times = 3;
            for (let i = 0; i < times; i++) {
                await ethers.provider.send("evm_mine", []);
                const reward = await stakingContract.pendingReward(0, owner.address);
                expect(reward).to.equal(tokenPerBlock.mul(i + 1));
            }

            let lastStaker1Reward: BigNumber;
            stakeToken.transfer(signers[1].address, "1000");
            stakeToken.transfer(signers[2].address, "1000");
            await stakeToken.connect(signers[1]).approve(stakingContract.address, "1000");
            const tx = await stakingContract.connect(signers[1]).stake(0, "1000", signers[1].address);
            {
                const reward = await stakingContract.pendingReward(0, owner.address);
                expect(reward).to.equal(tokenPerBlock.mul(tx.blockNumber as number - startBlock - 12));
                lastStaker1Reward = reward;
            }

            await stakeToken.connect(signers[2]).approve(stakingContract.address, "1000");
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                expect(staker1reward).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2)));
                expect(staker2reward).to.equal(tokenPerBlock.div(2));
            }

            await stakingContract.connect(signers[2]).stake(0, "1000", signers[2].address);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).mul(2)));
                expect(staker2reward).to.equal(tokenPerBlock.div(2).mul(2));
                expect(staker3reward).to.equal(BigNumber.from(0));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const value = tokenPerBlock.div(3);
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).mul(2)).add(value));
                expect(staker2reward).to.equal(tokenPerBlock.div(2).mul(2).add(value));
                expect(staker3reward).to.equal(value);
            }
        });

        it("Should receive the right reward after re stake", async function () {
            await stakeToken.approve(stakingContract.address, "1000");
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("86666666666666666666");
                expect(staker2reward.toString()).to.equal("16666666666666666666");
                expect(staker3reward.toString()).to.equal("6666666666666666666");
            }

            await stakingContract.stake(0, "1000", owner.address);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker3reward.toString()).to.equal("10000000000000000000");
                expect(staker2reward.toString()).to.equal("20000000000000000000");
                expect(staker1reward.toString()).to.equal("90000000000000000000");
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("95000000000000000000");
                expect(staker2reward.toString()).to.equal("22500000000000000000");
                expect(staker3reward.toString()).to.equal("12500000000000000000");
            }
        });

        it("Should receive the right reward after unstake", async function () {
            const oldBalance = await stakeToken.balanceOf(owner.address);
            await stakingContract.unstake(0, "1000", owner.address);
            const newBalance = await stakeToken.balanceOf(owner.address);
            expect(newBalance).to.equal(oldBalance.add("1000"));

            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("100000000000000000000");
                expect(staker2reward.toString()).to.equal("25000000000000000000");
                expect(staker3reward.toString()).to.equal("15000000000000000000");
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("103333333333333333333");
                expect(staker2reward.toString()).to.equal("28333333333333333333");
                expect(staker3reward.toString()).to.equal("18333333333333333333");
            }
        });

        it("Should receive the right reward after claim", async function () {
            const oldBalance = await rewardToken.balanceOf(owner.address);
            await stakingContract.claim(0, owner.address);
            const newBalance = await rewardToken.balanceOf(owner.address);
            expect(newBalance).to.equal(oldBalance.add("106666666666666666666"));

            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("0");
                expect(staker2reward.toString()).to.equal("31666666666666666666");
                expect(staker3reward.toString()).to.equal("21666666666666666666");
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("3333333333333333333");
                expect(staker2reward.toString()).to.equal("34999999999999999999");
                expect(staker3reward.toString()).to.equal("24999999999999999999");
            }
        });

        it("Should receive the right reward after unstake and claim", async function () {
            const oldStakeBalance = await stakeToken.balanceOf(owner.address);
            const oldRewardBalance = await rewardToken.balanceOf(owner.address);
            await stakingContract.unstakeAndClaim(0, "1000", owner.address);
            const newStakeBalance = await stakeToken.balanceOf(owner.address);
            const newRewardBalance = await rewardToken.balanceOf(owner.address);
            expect(newStakeBalance).to.equal(oldStakeBalance.add("1000"));
            expect(newRewardBalance).to.equal(oldRewardBalance.add("6666666666666666667"));

            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("0");
                expect(staker2reward.toString()).to.equal("38333333333333333333");
                expect(staker3reward.toString()).to.equal("28333333333333333333");
            }

            await ethers.provider.send("evm_mine", []);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward.toString()).to.equal("0");
                expect(staker2reward.toString()).to.equal("43333333333333333333");
                expect(staker3reward.toString()).to.equal("33333333333333333333");
            }
        });

        it("Should no reward if period end", async function () {
            let staker1reward: BigNumber;
            let staker2reward: BigNumber;
            let staker3reward: BigNumber;

            while (true) {
                const number = await ethers.provider.getBlockNumber();
                if (number >= startBlock + 112) {
                    staker1reward = await stakingContract.pendingReward(0, owner.address);
                    staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                    staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                    break
                }

                await ethers.provider.send("evm_mine", []);
            }

            await ethers.provider.send("evm_mine", []);

            const b1 = await stakingContract.pendingReward(0, owner.address);
            const b2 = await stakingContract.pendingReward(0, signers[1].address);
            const b3 = await stakingContract.pendingReward(0, signers[2].address);
            expect(staker1reward).to.equal(b1);
            expect(staker2reward).to.equal(b2);
            expect(staker3reward).to.equal(b3);
        });

        it("Should sum of rewards equals contract account balance", async function () {
            const staker1reward = await stakingContract.pendingReward(0, owner.address);
            const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
            const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
            const balance = await rewardToken.balanceOf(stakingContract.address);

            const sum = staker1reward.add(staker2reward).add(staker3reward);
            expect(sum).to.equals(balance.sub(1));
        });
    })

    describe("Next Period", function () {
        it("Should set the right period", async function () {
            await rewardToken.approve(stakingContract.address, tokenPerBlock.mul(100));
            await stakingContract.addPeriod(startBlock + 211, startBlock + 311, tokenPerBlock);
        });

        it("Should no reward if period not start", async function () {
            const staker1reward = await stakingContract.pendingReward(0, owner.address);
            const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
            const staker3reward = await stakingContract.pendingReward(0, signers[2].address);

            while (true) {
                const number = await ethers.provider.getBlockNumber();
                if (number >= startBlock + 211) {
                    break
                }

                await ethers.provider.send("evm_mine", []);
            }

            let b1 = await stakingContract.pendingReward(0, owner.address);
            let b2 = await stakingContract.pendingReward(0, signers[1].address);
            let b3 = await stakingContract.pendingReward(0, signers[2].address);
            expect(staker1reward).to.equal(b1);
            expect(staker2reward).to.equal(b2);
            expect(staker3reward).to.equal(b3);
        });

        it("Should receive the right reward", async function () {
            await stakeToken.approve(stakingContract.address, "1000");

            const staker1reward = await stakingContract.pendingReward(0, owner.address);
            const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
            const staker3reward = await stakingContract.pendingReward(0, signers[2].address);

            await stakingContract.stake(0, "1000", owner.address);

            const b1 = await stakingContract.pendingReward(0, owner.address);
            const b2 = await stakingContract.pendingReward(0, signers[1].address);
            const b3 = await stakingContract.pendingReward(0, signers[2].address);

            expect(b1).to.equal(staker1reward);
            expect(b2).to.equal(staker2reward.add(tokenPerBlock.div(2)));
            expect(b3).to.equal(staker3reward.add(tokenPerBlock.div(2)));

            await ethers.provider.send("evm_mine", []);

            expect(await stakingContract.pendingReward(0, owner.address)).to.equal(b1.add(b1.add(tokenPerBlock.div(3))));
            expect(await stakingContract.pendingReward(0, signers[1].address)).to.equal(b2.add(tokenPerBlock.div(3)));
            expect(await stakingContract.pendingReward(0, signers[2].address)).to.equal(b3.add(tokenPerBlock.div(3)));
        })
    })

    describe("Redeploy", function () {
        it("Redeploy all contracts", async function () {
            startBlock = await ethers.provider.getBlockNumber();

            const ERC20 = await ethers.getContractFactory("ERC20Token");
            stakeToken = await ERC20.deploy("Stake Token", "STAKE", "10000000000000000000000"); // blocknumber 1
            stakeToken2 = await ERC20.deploy("Stake Token2", "STAKE2", "10000000000000000000000"); // blocknumber 2
            rewardToken = await ERC20.deploy("Reward Token", "REWARD", "10000000000000000000000"); // blocknumber 3

            const StakingContract = await ethers.getContractFactory("StakingSharedPoolL2");
            stakingContract = await StakingContract.deploy(rewardToken.address); // blocknumber 4
    
            await stakingContract.add(100, stakeToken.address); // blocknumber 5
            await stakingContract.add(100, stakeToken2.address); // blocknumber 6
        });
    })

    describe("Multiple pools", function () {
        it("Should set the right period", async function () {
            await rewardToken.approve(stakingContract.address, tokenPerBlock.mul(100)); // blocknumber 7
            await stakingContract.addPeriod(startBlock + 12, startBlock + 112, tokenPerBlock); // blocknumber 8

            const balance = await rewardToken.balanceOf(stakingContract.address);
            expect(balance).to.equals(tokenPerBlock.mul(100));
        });

        it("Should set the right stake amount", async function () {
            await stakeToken.approve(stakingContract.address, "1000"); // blocknumber 9
            await stakeToken2.approve(stakingContract.address, "1000"); // blocknumber 10
            await stakingContract.stake(0, "1000", owner.address); // blocknumber 11
            const tx = await stakingContract.stake(1, "1000", owner.address); // blocknumber 12
            expect(tx.blockNumber as number).to.equal(startBlock + 12);
        });

        it("Should receive the right reward", async function () {
            const times = 3;
            for (let i = 0; i < times; i++) {
                await ethers.provider.send("evm_mine", []);

                const reward = await stakingContract.pendingReward(0, owner.address);
                expect(reward).to.equal(tokenPerBlock.div(2).mul(i + 1));

                const reward2 = await stakingContract.pendingReward(1, owner.address);
                expect(reward2).to.equal(tokenPerBlock.div(2).mul(i + 1));
            }

            let lastStaker1Reward: BigNumber;
            stakeToken.transfer(signers[1].address, "1000");
            stakeToken.transfer(signers[2].address, "1000");
            await stakeToken.connect(signers[1]).approve(stakingContract.address, "1000");
            const tx = await stakingContract.connect(signers[1]).stake(0, "1000", signers[1].address);
            {
                const reward = await stakingContract.pendingReward(0, owner.address);
                expect(reward).to.equal(tokenPerBlock.div(2).mul(tx.blockNumber as number - startBlock - 12));

                const reward2 = await stakingContract.pendingReward(1, owner.address);
                expect(reward2).to.equal(tokenPerBlock.div(2).mul(tx.blockNumber as number - startBlock - 12));

                lastStaker1Reward = reward;
            }

            await stakeToken.connect(signers[2]).approve(stakingContract.address, "1000");
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                expect(staker1reward).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).div(2)));
                expect(staker2reward).to.equal(tokenPerBlock.div(2).div(2));

                const staker1reward2 = await stakingContract.pendingReward(1, owner.address);
                const staker2reward2 = await stakingContract.pendingReward(1, signers[1].address);
                expect(staker1reward2).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2)));
                expect(staker2reward2).to.equal(BigNumber.from(0));
            }

            await stakingContract.connect(signers[2]).stake(0, "1000", signers[2].address);
            {
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).div(2).mul(2)));
                expect(staker2reward).to.equal(tokenPerBlock.div(2).div(2).mul(2));
                expect(staker3reward).to.equal(BigNumber.from(0));

                const staker1reward2 = await stakingContract.pendingReward(1, owner.address);
                const staker2reward2 = await stakingContract.pendingReward(1, signers[1].address);
                const staker3reward2 = await stakingContract.pendingReward(1, signers[2].address);
                expect(staker1reward2).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).mul(2)));
                expect(staker2reward2).to.equal(BigNumber.from(0));
                expect(staker3reward2).to.equal(BigNumber.from(0));
            }

            await ethers.provider.send("evm_mine", []);
            {
                const value = tokenPerBlock.div(2).div(3);
                const staker1reward = await stakingContract.pendingReward(0, owner.address);
                const staker2reward = await stakingContract.pendingReward(0, signers[1].address);
                const staker3reward = await stakingContract.pendingReward(0, signers[2].address);
                expect(staker1reward).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).div(2).mul(2)).add(value));
                expect(staker2reward).to.equal(tokenPerBlock.div(2).div(2).mul(2).add(value));
                expect(staker3reward).to.equal(value);

                const staker1reward2 = await stakingContract.pendingReward(1, owner.address);
                const staker2reward2 = await stakingContract.pendingReward(1, signers[1].address);
                const staker3reward2 = await stakingContract.pendingReward(1, signers[2].address);
                expect(staker1reward2).to.equal(lastStaker1Reward.add(tokenPerBlock.div(2).mul(3)));
                expect(staker2reward2).to.equal(BigNumber.from(0));
                expect(staker3reward2).to.equal(BigNumber.from(0));
            }
        });
    })

    describe("Kill", function () {
        it("Should self destruct", async function () {
            await stakingContract.kill();
        });
    })
});
