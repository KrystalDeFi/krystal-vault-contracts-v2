import { IConfig } from "./interfaces";

export const EthereumConfig: Record<string, IConfig> = {
  ethereum_mainnet: {
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
    wrapToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    typedTokens: [
      "0xA0b86991C6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
      "0xdAC17F958D2ee523a2206206994597C13D831ec7", // USDT
      "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
      "0x7f39c581f595b53c5cb5bb5985fab2e2d7d6a7d8", // wstETH
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WETH
      2, // wstETH
    ],
    swapRouters: ["0x70270C228c5B4279d1578799926873aa72446CcD"],
  },
};
