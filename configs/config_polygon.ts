import { IConfig } from "./interfaces";

export const PolygonConfig: Record<string, IConfig> = {
  polygon_mainnet: {
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
    merklAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    wrapToken: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    typedTokens: [
      "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359", // USDC
      "0xc2132d05d31c914a87c6611c10748aeb04b58e8f", // USDT
      "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", // DAI
      "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
      "0xc2132D05D31c914a87C6611C10748Aaeb04B58e8", // USDT
      "0x750e4c4984a9e0f12978ea6742bc1c5d248f40ed", // AXLUSDC
      "0x3a58a54c066fdc0f2d55fc9c89f0415c92ebf3c4", // STMATIC
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // WPOL
      "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619", // WETH
      "0x03b54a6e9a984069379fae1a4fc4dbae93b3bccd", // wstETH
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      1, // USDC
      1, // USDT
      1, // AXLUSDC
      2, // STMATIC
      2, // WPOL
      3, // WETH
      3, // wstETH
    ],
    swapRouters: ["0x70270C228c5B4279d1578799926873aa72446CcD"],
  },
};
