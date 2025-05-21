import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "solidity-docgen";
import "@nomicfoundation/hardhat-foundry";

import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/types/config";

dotenv.config({
  path: "./.env",
});

const {
  PRIVATE_KEY,
  BASESCAN_APIKEY,
  ETHERSCAN_APIKEY,
  ARBISCAN_APIKEY,
  POLYGONSCAN_APIKEY,
  OPTIMISM_APIKEY,
  BSCSCAN_APIKEY,
  BERASCAN_APIKEY,
  ETHERSCAN_V2_APIKEY,
} = process.env;
const customNetworkConfig = process.env.CHAIN && process.env.CHAIN ? `${process.env.CHAIN}_${process.env.NETWORK}` : "";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 150,
          },
          evmVersion: "cancun",
          metadata: {
            bytecodeHash: "none",
          },
        },
      },
    ],
  },
  defaultNetwork: "hardhat",
  gasReporter: {
    currency: "USD",
    gasPrice: 100,
    enabled: true,
  },
  abiExporter: {
    clear: true,
    path: "./abi",
    runOnCompile: true,
    flat: false,
    spacing: 2,
    pretty: false,
  },
  paths: {
    sources: "./contracts",
    tests: "./test/",
  },
  mocha: {
    timeout: 2000000,
    parallel: false,
    fullTrace: true,
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      forking: {
        enabled: true,
        url: `https://base.llamarpc.com`,
        blockNumber: 26313000,
      },
      accounts: {
        count: 10,
      },
      hardfork: "cancun",
    },
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_APIKEY || "",
      base: BASESCAN_APIKEY || "",
      optimisticEthereum: OPTIMISM_APIKEY || "",
      bsc: BSCSCAN_APIKEY || "",
      polygon: POLYGONSCAN_APIKEY || "",
      arbitrumOne: ARBISCAN_APIKEY || "",
      berachain: BERASCAN_APIKEY || "",
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org",
        },
      },
      {
        network: "berachain",
        chainId: 80094,
        urls: {
          apiURL: "https://api.berascan.com/api",
          browserURL: "https://berascan.com",
        },
      },
    ],
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
  docgen: {
    outputDir: "docs",
    theme: "markdown",
    pages: "files",
    pageExtension: ".md",
    exclude: ["contracts/interfaces/ICreateX.sol"],
  },
};

if (PRIVATE_KEY) {
  config.networks!.base_mainnet = {
    url: `https://mainnet.base.org`,
    chainId: 8453,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
  config.networks!.eth_mainnet = {
    url: `https://eth.llamarpc.com`,
    chainId: 1,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
  config.networks!.bsc_mainnet = {
    url: `https://binance.llamarpc.com`,
    chainId: 56,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
  config.networks!.polygon_mainnet = {
    url: `https://polygon-rpc.com`,
    chainId: 137,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
  config.networks!.optimism_mainnet = {
    url: `https://op-pokt.nodies.app`,
    chainId: 10,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
  config.networks!.arbitrum_mainnet = {
    url: `https://arbitrum-one-rpc.publicnode.com`,
    chainId: 42161,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
  config.networks!.berachain_mainnet = {
    url: `https://berachain-rpc.publicnode.com`,
    chainId: 80094,
    accounts: [PRIVATE_KEY],
    timeout: 60000,
    hardfork: "cancun",
  };
}

export default config;
