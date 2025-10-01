import { AddressLike } from "ethers";

export interface IConfigPrivate {
  privateVault?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privateVaultFactory?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privateConfigManager?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privateVaultAutomator?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privateAerodromeFarmingStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privatePancakeV3FarmingStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privateV3UtilsStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  privateV4UtilsStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  v3UtilsAddress?: AddressLike;
  v4UtilsAddress?: AddressLike;
  aerodromeGaugeFactory?: AddressLike;
  pancakeV3MasterChef?: AddressLike;
}

export interface IConfigAerodrome {
  lpStrategyAerodrome?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  lpValidatorAerodrome?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  rewardSwapper?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  farmingStrategyValidator?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  farmingStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  vaultAutomatorAerodrome?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  aerodromeNfpmAddresses?: AddressLike[];
  aerodromeGaugeFactories?: AddressLike[];
}

export interface IConfig extends IConfigPrivate, IConfigAerodrome {
  autoVerifyContract?: boolean;
  sleepTime?: number;
  vault: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  vaultAutomator: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  vaultFactory: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  configManager?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  poolOptimalSwapper?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  katanaPoolOptimalSwapper?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  lpValidator?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  lpFeeTaker?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  katanaLpFeeTaker?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  lpStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  lpChainingStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  merklStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  merklAutomator?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  kodiakIslandStrategy?: {
    enabled?: boolean;
    autoVerifyContract?: boolean;
  };
  wrapToken?: string;
  typedTokens?: string[];
  // 0 for stable, 1 for pegged,...
  typedTokensTypes?: number[];
  encodedLpConfigs?: string[];
  swapRouters: AddressLike[];
  nfpmAddresses: AddressLike[];

  katanaAggregateSwapRouter?: AddressLike;
  rewardVaultFactory?: string;
  bgtToken?: string;
  wbera?: string;
}
