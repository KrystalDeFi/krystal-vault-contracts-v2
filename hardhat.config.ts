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

const { PRIVATE_KEY, BASESCAN_APIKEY } = process.env;
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
            runs: 1500,
            details: {
              yul: true,
            },
          },
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
      base: BASESCAN_APIKEY || "",
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://api.basescan.org",
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
}

export default config;
