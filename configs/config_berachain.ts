import { commonConfig } from "./config_common";
import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  berachain_mainnet: {
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
    privateAerodromeFarmingStrategy: {
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
    v3UtilsAddress: "0x3A7e46212Ac7d61E44bb9bA926E3737Af5A65EC6",
    v4UtilsAddress: "0xE91D4cC5d8b97379d740A1f19c728EAb76A16228",
  },
};

export const BerachainConfig: Record<string, IConfig> = {
  berachain_mainnet: {
    sleepTime: 20000,
    vault: {
      enabled: true,
      autoVerifyContract: true,
    },
    vaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    configManager: {
      enabled: true,
      autoVerifyContract: true,
    },
    poolOptimalSwapper: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpValidator: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpFeeTaker: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpChainingStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    merklStrategy: {
      enabled: false,
      autoVerifyContract: true,
    },
    merklAutomator: {
      enabled: false,
      autoVerifyContract: true,
    },
    vaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    kodiakIslandStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    wrapToken: "0x6969696969696969696969696969696969696969", // WBERA
    typedTokens: [
      "0x6969696969696969696969696969696969696969", // WBERA
      "0xfcbd14dc51f0a4d49d5e53c2e0950e0bc26d0dce", // HONEY
      "0x5d3a1ff2b6bab83b63cd9ad0787074081a52ef34", // USDe
      "0x0555e30da8f98308edb960aa94c0db47230d2b9c", // WBTC
    ],
    typedTokensTypes: [2, 1, 1, 3],
    encodedLpConfigs: [
      "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fd70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b4aeaab10258f4000000000000000000000000000000000000000000000000070efc4d0e326fb4000000000000000000000000000000000000000000000000469604a4b21353340000",
      commonConfig.stableConfigWith18Decimals,
      commonConfig.stableConfigWith18Decimals,
    ],
    swapRouters: [],
    nfpmAddresses: ["0xFE5E8C83FFE4d9627A75EaA7Fee864768dB989bD"],
    rewardVaultFactory: "0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8",
    bgtToken: "0x656b95E550C07a9ffe548bd4085c72418Ceb1dba",
    wbera: "0x6969696969696969696969696969696969696969",
    ...PrivateConfig.berachain_mainnet,
  },
};
