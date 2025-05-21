import { IConfig } from "./interfaces";
import { BaseConfig } from "./config_base";
import { ArbitrumConfig } from "./config_arbitrum";
import { BscConfig } from "./config_bsc";
import { EthereumConfig } from "./config_eth";
import { OptimismConfig } from "./config_optimism";
import { PolygonConfig } from "./config_polygon";
import { BerachainConfig } from "./config_berachain";

const NetworkConfig: Record<string, IConfig> = {
  ...BaseConfig,
  ...ArbitrumConfig,
  ...BscConfig,
  ...EthereumConfig,
  ...OptimismConfig,
  ...PolygonConfig,
  ...BerachainConfig,
};

export { NetworkConfig };
