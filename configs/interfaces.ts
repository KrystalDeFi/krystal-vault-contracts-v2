import { AddressLike } from "ethers";

export interface IConfig {
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
  // Aerodrome contracts
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
  // -------------------
  wrapToken?: string;
  typedTokens?: string[];
  // 0 for stable, 1 for pegged,...
  typedTokensTypes?: number[];
  encodedLpConfigs?: string[];
  swapRouters: AddressLike[];
  nfpmAddresses: AddressLike[];
  aerodromeNfpmAddresses?: AddressLike[];

  katanaAggregateSwapRouter?: AddressLike;
  rewardVaultFactory?: string;
  bgtToken?: string;
  wbera?: string;
  aerodromeGaugeFactories?: AddressLike[];
}
