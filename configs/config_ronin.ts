import { commonConfig } from "./config_common";
import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  ronin_mainnet: {
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

export const RoninConfig: Record<string, IConfig> = {
  ronin_mainnet: {
    sleepTime: 20000,
    vault: {
      enabled: true,
      autoVerifyContract: true,
    },
    vaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    vaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    configManager: {
      enabled: true,
      autoVerifyContract: true,
    },
    katanaPoolOptimalSwapper: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpValidator: {
      enabled: true,
      autoVerifyContract: true,
    },
    katanaLpFeeTaker: {
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
      enabled: true,
      autoVerifyContract: true,
    },
    merklAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    wrapToken: "0xe514d9deb7966c8be0ca922de8a064264ea6bcd4",
    typedTokens: [
      "0xc99a6a985ed2cac1ef41640596c5a5f9f4e19ef5", // WETH
      "0x0b7007c13325c48911f73a2dad5fa5dcbf808adc", // USDC
      "0xe514d9deb7966c8be0ca922de8a064264ea6bcd4", // RON
      "0xcad9e7aa2c3ef07bad0a7b69f97d059d8f36edd2", // LRON
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      3, // WETH
      1, // USDC
      2, // RON
      2, // LRON
    ],
    encodedLpConfigs: [
      commonConfig.nativeConfig,
      commonConfig.stableConfigWith6Decimals,
      "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fd700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000032d26d12e980b600000000000000000000000000000000000000000000000001fc3842bd1f071c00000000000000000000000000000000000000000000000013da329b6336471800000",
    ],
    swapRouters: ["0xfEE93FCD1a26e858325613818dE5C533d94A33b6"],
    nfpmAddresses: ["0x7cF0fb64d72b733695d77d197c664e90D07cF45A"],

    katanaAggregateSwapRouter: "0x5F0aCDD3eC767514fF1BF7e79949640bf94576BD",
    ...PrivateConfig.ronin_mainnet,
  },
};
