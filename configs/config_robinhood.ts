import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  robinhood_mainnet: {
    privateVault: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateVaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateConfigManager: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateVaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateV3UtilsStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateV4UtilsStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    v3UtilsAddress: "0xb4acbC082b5e7dEd571c98EE4257778a9D784B36",
    v4UtilsAddress: "0xCb3d2a42022741B06f9B38459e3DD1Ee9A64D129",
  },
};

// Robinhood Chain (Arbitrum Orbit L2, chain id 4663) — private-vault-only deployment.
// Uniswap V3 is live; the public/shared vault stacks are not deployed here.
export const RobinhoodConfig: Record<string, IConfig> = {
  robinhood_mainnet: {
    sleepTime: 20000,
    vault: {
      enabled: false,
    },
    vaultAutomator: {
      enabled: false,
    },
    vaultFactory: {
      enabled: false,
    },
    swapRouters: [],
    nfpmAddresses: [
      "0x73991a25c818bf1f1128deaab1492d45638de0d3", // Uniswap V3
      "0x58daec3116aae6d93017baaea7749052e8a04fa7", // Uniswap V4
    ],
    ...PrivateConfig.robinhood_mainnet,
  },
};
