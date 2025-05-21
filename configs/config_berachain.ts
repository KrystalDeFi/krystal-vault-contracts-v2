import { IConfig } from "./interfaces";

export const BerachainConfig: Record<string, IConfig> = {
  berachain_mainnet: {
    sleepTime: 60000,
    vault: {
      enabled: true,
      autoVerifyContract: true,
    },
    vaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    configManager: {
      enabled: false,
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
    ],
    typedTokensTypes: [1],
    swapRouters: [],
    nfpmAddresses: ["0xFE5E8C83FFE4d9627A75EaA7Fee864768dB989bD"],
    rewardVaultFactory: "0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8",
    bgtToken: "0x656b95E550C07a9ffe548bd4085c72418Ceb1dba",
    wbera: "0x6969696969696969696969696969696969696969",
  },
};
