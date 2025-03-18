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
    lpStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    wrapToken: "0x4200000000000000000000000000000000000006",
    stableTokens: [
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", // USDC
      "0xfde4c96c8593536e31f229ea8f37b2ada2699bb2", // USDT
      "0x50c5725949a6f0c72e6c4a641f24049a917db0cb", // DAI
    ],
    automatorAddress: "0xC1149cDA92B99CD17Ce66D82E599707f91D24BcA",
    platformFeeRecipient: "0xC1149cDA92B99CD17Ce66D82E599707f91D24BcA",
    platformFeeBasisPoint: 50,
  },
};
