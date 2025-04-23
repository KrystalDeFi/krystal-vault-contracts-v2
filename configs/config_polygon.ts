import { IConfig } from "./interfaces";

export const PolygonConfig: Record<string, IConfig> = {
  polygon_mainnet: {
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
    wrapToken: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    typedTokens: [
      "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
      "0xc2132D05D31c914a87C6611C10748Aaeb04B58e8", // USDT
      "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", // DAI
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // WPOL
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WPOL
    ],
    swapRouters: ["0x70270C228c5B4279d1578799926873aa72446CcD"],
  },
};
