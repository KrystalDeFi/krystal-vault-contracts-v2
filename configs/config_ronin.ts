import { IConfig } from "./interfaces";

export const RoninConfig: Record<string, IConfig> = {
  ronin_mainnet: {
    sleepTime: 10000,
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
    swapRouters: ["0xfEE93FCD1a26e858325613818dE5C533d94A33b6"],
    nfpmAddresses: ["0x7cF0fb64d72b733695d77d197c664e90D07cF45A"],

    katanaAggregateSwapRouter: "0x5F0aCDD3eC767514fF1BF7e79949640bf94576BD",
  },
};
