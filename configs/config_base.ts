import { IConfig, ITestConfig } from "./interfaces";

export const BaseConfig: Record<string, IConfig> = {
  base_mainnet: {
    sleepTime: 6 * 1000,
    poolOptimalSwapper: {
      enabled: true,
      autoVerifyContract: true,
    },
    krystalVault: {
      enabled: true,
      autoVerifyContract: true,
    },
    krystalVaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    krystalVaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    uniswapV3Factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
    automatorAddress: "0xC1149cDA92B99CD17Ce66D82E599707f91D24BcA",
    platformFeeRecipient: "0xC1149cDA92B99CD17Ce66D82E599707f91D24BcA",
    platformFeeBasisPoint: 50,
    ownerFeeBasisPoint: 50,
  },
};

export const BaseTestConfig: Record<string, ITestConfig> = {
  base_mainnet: {
    nfpm: "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
  },
};
