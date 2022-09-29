import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

// Load environment variables.
dotenv.config();
const { NODE_URL, PRIVATE_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },

  networks: {
    mainnet: {
      url: NODE_URL,
      accounts: PRIVATE_KEY ? [ PRIVATE_KEY ] : []
    },
    goerli: {
      url: NODE_URL,
      accounts: PRIVATE_KEY ? [ PRIVATE_KEY ] : []
    },
    polygon: {
      url: NODE_URL,
      accounts: PRIVATE_KEY ? [ PRIVATE_KEY ] : []
    },
    bsc: {
      url: NODE_URL,
      accounts: PRIVATE_KEY ? [ PRIVATE_KEY ] : []
    },
  }
};

export default config;
