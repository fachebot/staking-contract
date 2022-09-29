import { HardhatUserConfig } from "hardhat/config";
import { HttpNetworkUserConfig } from "hardhat/types/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

// Load environment variables.
dotenv.config();
const { NODE_URL, PRIVATE_KEY } = process.env;

const networkConfig: HttpNetworkUserConfig = {};
if (PRIVATE_KEY) {
  networkConfig.accounts = [PRIVATE_KEY];
}
networkConfig.url = NODE_URL ? NODE_URL : "http://localhost:8545";

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
      ...networkConfig
    },
    goerli: {
      ...networkConfig
    },
    polygon: {
      ...networkConfig
    },
    bsc: {
      ...networkConfig
    },
  }
};

export default config;
