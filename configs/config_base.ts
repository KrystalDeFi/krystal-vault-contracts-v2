import { IConfig, ITestConfig } from "./interfaces";

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
    vaultZapper: {
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
    // wrap token of chain must be the first token
    lpStrategyPrincipalTokens: ["0x4200000000000000000000000000000000000006"],
    automatorAddress: "0xC1149cDA92B99CD17Ce66D82E599707f91D24BcA",
    platformFeeRecipient: "0xC1149cDA92B99CD17Ce66D82E599707f91D24BcA",
    platformFeeBasisPoint: 50,
  },
};

export const BaseTestConfig: Record<string, ITestConfig> = {
  base_mainnet: {
    nfpm: "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
  },
};
