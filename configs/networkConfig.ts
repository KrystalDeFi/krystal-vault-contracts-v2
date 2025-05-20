import { IConfig } from "./interfaces";
import { BaseConfig } from "./config_base";
import { ArbitrumConfig } from "./config_arbitrum";
import { BscConfig } from "./config_bsc";
import { EthereumConfig } from "./config_eth";
import { OptimismConfig } from "./config_optimism";
import { PolygonConfig } from "./config_polygon";
import { RoninConfig } from "./config_ronin";

const NetworkConfig: Record<string, IConfig> = {
  ...BaseConfig,
  ...ArbitrumConfig,
  ...BscConfig,
  ...EthereumConfig,
  ...OptimismConfig,
  ...PolygonConfig,
  ...RoninConfig,
};

NetworkConfig.hardhat = {
  // In case of testing, fork the config of the particular chain to hardhat
  ...NetworkConfig["base_mainnet"],
  ...NetworkConfig["arbitrum_mainnet"],
  ...NetworkConfig["bsc_mainnet"],
  ...NetworkConfig["eth_mainnet"],
  ...NetworkConfig["optimism_mainnet"],
  ...NetworkConfig["polygon_mainnet"],
  ...NetworkConfig["ronin_mainnet"],
  autoVerifyContract: false,
};

export { NetworkConfig };
