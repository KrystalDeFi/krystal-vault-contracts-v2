import { IConfig } from "./interfaces";

export const OptimismConfig: Record<string, IConfig> = {
  optimism_mainnet: {
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
    wrapToken: "0x4200000000000000000000000000000000000006",
    typedTokens: [
      "0x7F5c764cBc14f9669B88837ca1490cCa17c31607", // USDC
      "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58", // USDT
      "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1", // DAI
      "0x4200000000000000000000000000000000000006", // WETH
      "0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb", // wstETH
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WETH
      2, // wstETH
    ],
    swapRouters: ["0xf6f2dafa542FefAae22187632Ef30D2dAa252b4e"],
    nfpmAddresses: ["0xC36442b4a4522E871399CD717aBDD847Ab11FE88", "0x1af415a1EbA07a4986a52B6f2e7dE7003D82231e"],
  },
};
