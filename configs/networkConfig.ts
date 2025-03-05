import { IConfig } from "./interfaces";
import { BaseConfig } from "./config_base";

const NetworkConfig: Record<string, IConfig> = {
  ...BaseConfig,
};

NetworkConfig.hardhat = {
  // In case of testing, fork the config of the particular chain to hardhat
  ...NetworkConfig["base_mainnet"],
  autoVerifyContract: false,
};

export { NetworkConfig };
