import { IConfig } from "./interfaces";

export const BaseConfig: Record<string, IConfig> = {
  base_mainnet: {
    sleepTime: 6 * 1000,
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
    merklStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    wrapToken: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
    typedTokens: [
      "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d", // USDC
      "0x55d398326f99059ff775485246999027b3197955", // USDT
      "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3", // DAI
      "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", // WBNB
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WBNB
    ],
  },
};
