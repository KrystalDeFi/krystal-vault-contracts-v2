import { ethers, network, run } from "hardhat";
import { NetworkConfig } from "../configs/networkConfig";
import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { IConfig } from "../configs/interfaces";
import { sleep } from "./helpers";
import { isArray } from "lodash";
import { PoolOptimalSwapper, Vault, VaultFactory, ConfigManager } from "../typechain-types/contracts/public-vault/core";
import {
  LpFeeTaker,
  LpStrategy,
  LpValidator,
  VaultAutomator,
} from "../typechain-types/contracts/public-vault/strategies/lpUniV3";
import { KodiakIslandStrategy } from "../typechain-types/contracts/public-vault/strategies/kodiak";
import { commonConfig } from "../configs/config_common";
import { MerklStrategy } from "../typechain-types";
import { MerklAutomator } from "../typechain-types/contracts/public-vault/strategies/merkl";
import {
  KatanaLpFeeTaker,
  KatanaPoolOptimalSwapper,
} from "../typechain-types/contracts/public-vault/strategies/roninKatanaV3";
import { LpChainingStrategy } from "../typechain-types/contracts/public-vault/strategies/lpChaining";
import {
  LpStrategy as LpStrategyAerodrome,
  LpValidator as LpValidatorAerodrome,
  FarmingStrategy,
  RewardSwapper,
  VaultAutomator as VaultAutomatorAerodrome,
} from "../typechain-types/contracts/public-vault/strategies/lpAerodrome";

const { SALT } = process.env;

const createXContractAddress = "0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed";
const createXTopic = "0xb8fda7e00c6b06a2b54e58521bc5894fee35f1090e5a3bb6390bfe2b98b497f7";

const isRonin = network.name === "ronin_mainnet";
const isBera = network.name === "berachain_mainnet";
const isHyperevm = network.name === "hyperevm_mainnet";
const contractAdmin = isRonin ? commonConfig.roninAdmin : isHyperevm ? commonConfig.hyperevmAdmin : commonConfig.admin;

const networkConfig = NetworkConfig[network.name];
if (!networkConfig) {
  throw new Error(`Missing deploy config for ${network.name}`);
}

export interface Contracts {
  vault?: Vault;
  vaultAutomator?: VaultAutomator;
  configManager?: ConfigManager;
  poolOptimalSwapper?: PoolOptimalSwapper | KatanaPoolOptimalSwapper;
  lpValidator?: LpValidator;
  lpFeeTaker?: LpFeeTaker | KatanaLpFeeTaker;
  lpStrategy?: LpStrategy;
  lpChainingStrategy?: LpChainingStrategy;
  merklStrategy?: MerklStrategy;
  merklAutomator?: MerklAutomator;
  vaultFactory?: VaultFactory;
  kodiakIslandStrategy?: KodiakIslandStrategy;
  // Aerodrome contracts
  lpValidatorAerodrome?: LpValidatorAerodrome;
  lpStrategyAerodrome?: LpStrategyAerodrome;
  rewardSwapper?: RewardSwapper;
  farmingStrategy?: FarmingStrategy;
  vaultAutomatorAerodrome?: VaultAutomatorAerodrome;
  // --------------------
}

export const deploy = async (existingContract: Record<string, any> | undefined = undefined): Promise<Contracts> => {
  const [deployer] = await ethers.getSigners();

  const deployerAddress = await deployer.getAddress();

  log(0, "Start deployin contracts");
  log(0, "======================\n");

  let deployedContracts = await deployContracts(existingContract);

  // Summary
  log(0, "Summary");
  log(0, "=======\n");

  log(0, JSON.stringify(convertToAddressObject(deployedContracts), null, 2));

  console.log("\nDeployment complete!");
  return deployedContracts;
};

async function deployContracts(existingContract: Record<string, any> | undefined = undefined): Promise<Contracts> {
  let step = 0;

  const vault = await deployVaultContract(++step, existingContract);
  const vaultAutomator = await deployVaultAutomatorContract(++step, existingContract);
  const vaultAutomatorAerodrome = await deployVaultAutomatorAerodromeContract(++step, existingContract);
  const poolOptimalSwapper = await deployPoolOptimalSwapperContract(++step, existingContract);
  const katanaPoolOptimalSwapper = await deployKatanaPoolOptimalSwapperContract(++step, existingContract);

  const contracts: Contracts = {
    vault: vault.vault,
    vaultAutomator: vaultAutomator.vaultAutomator,
    vaultAutomatorAerodrome: vaultAutomatorAerodrome.vaultAutomatorAerodrome,
    poolOptimalSwapper: isRonin ? katanaPoolOptimalSwapper.poolOptimalSwapper : poolOptimalSwapper.poolOptimalSwapper,
  };

  const configManager = await deployConfigManagerContract(++step, existingContract, undefined, contracts);

  Object.assign(contracts, {
    configManager: configManager.configManager,
  });

  const lpValidator = await deployLpValidatorContract(++step, existingContract, undefined, contracts);
  const lpValidatorAerodrome = await deployLpValidatorAerodromeContract(++step, existingContract, undefined, contracts);
  const lpFeeTaker = await deployLpFeeTakerContract(++step, existingContract, undefined, contracts);
  const katanaLpFeeTaker = await deployKatanaLpFeeTakerContract(++step, existingContract, undefined, contracts);
  const merklAutomator = await deployMerklAutomatorContract(++step, existingContract, undefined, contracts);
  const rewardSwapper = await deployRewardSwapperContract(++step, existingContract, undefined, contracts);

  Object.assign(contracts, {
    lpValidator: lpValidator.lpValidator,
    lpValidatorAerodrome: lpValidatorAerodrome.lpValidatorAerodrome,
    lpFeeTaker: isRonin ? katanaLpFeeTaker.lpFeeTaker : lpFeeTaker.lpFeeTaker,
    merklAutomator: merklAutomator.merklAutomator,
    rewardSwapper: rewardSwapper.rewardSwapper,
  });

  const lpStrategy = await deployLpStrategyContract(++step, existingContract, undefined, contracts);
  const lpStrategyAerodrome = await deployLpStrategyAerodromeContract(++step, existingContract, undefined, contracts);
  const lpChainingStrategy = await deployLpChainingStrategyContract(++step, existingContract, undefined, contracts);
  const merklStrategy = await deployMerklStrategyContract(++step, existingContract, undefined, contracts);
  const vaultFactory = await deployVaultFactoryContract(++step, existingContract, undefined, contracts);
  const kodiakIslandStrategy = await deployKodiakIslandStrategyContract(++step, existingContract, undefined, contracts);

  Object.assign(contracts, {
    lpStrategy: lpStrategy.lpStrategy,
    lpStrategyAerodrome: lpStrategyAerodrome.lpStrategyAerodrome,
    lpChainingStrategy: lpChainingStrategy.lpChainingStrategy,
    vaultFactory: vaultFactory.vaultFactory,
    merklStrategy: merklStrategy.merklStrategy,
    kodiakIslandStrategy: kodiakIslandStrategy.kodiakIslandStrategy,
  });

  const farmingStrategy = await deployFarmingStrategyContract(++step, existingContract, undefined, contracts);

  Object.assign(contracts, {
    farmingStrategy: farmingStrategy.farmingStrategy,
  });

  if (networkConfig.vaultFactory.enabled) {
    await vaultFactory?.vaultFactory?.initialize(
      contractAdmin,
      networkConfig.wrapToken || "",
      existingContract?.["configManager"] || contracts?.configManager?.target,
      existingContract?.["vault"] || contracts?.vault?.target,
    );
  }

  if (networkConfig.configManager?.enabled) {
    let lpValidators;
    let typedTokens;
    let configs;

    if (isRonin) {
      lpValidators = [
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
      ];
      typedTokens = [
        networkConfig?.typedTokens?.[0] || "",
        networkConfig?.typedTokens?.[1] || "",
        networkConfig?.wrapToken || "",
      ];
      configs = networkConfig.encodedLpConfigs || [];
    } else if (isBera) {
      lpValidators = [
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
      ];
      typedTokens = [
        networkConfig?.wrapToken || "",
        networkConfig?.typedTokens?.[1] || "",
        networkConfig?.typedTokens?.[2] || "",
      ];
      configs = networkConfig.encodedLpConfigs || [];
    } else if (isHyperevm) {
      lpValidators = [
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
      ];
      typedTokens = [
        networkConfig?.wrapToken || "",
        networkConfig?.typedTokens?.[0] || "",
        networkConfig?.typedTokens?.[2] || "",
        networkConfig?.typedTokens?.[4] || "",
        networkConfig?.typedTokens?.[5] || "",
        networkConfig?.typedTokens?.[9] || "",
        networkConfig?.typedTokens?.[10] || "",
        networkConfig?.typedTokens?.[11] || "",
        networkConfig?.typedTokens?.[12] || "",
        networkConfig?.typedTokens?.[13] || "",
      ];
      configs = networkConfig.encodedLpConfigs || [];
    } else {
      lpValidators = [
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
      ];
      typedTokens = [
        networkConfig?.wrapToken || "",
        networkConfig?.typedTokens?.[0] || "",
        networkConfig?.typedTokens?.[1] || "",
        networkConfig?.typedTokens?.[2] || "",
      ];
      configs = [
        commonConfig.nativeConfig,
        commonConfig.stableConfigWith6Decimals,
        commonConfig.stableConfigWith6Decimals,
        commonConfig.stableConfigWith18Decimals,
      ];
    }

    await configManager?.configManager?.initialize(
      contractAdmin,
      [
        existingContract?.["lpStrategy"] || contracts?.lpStrategy?.target,
        existingContract?.["lpChainingStrategy"] || contracts?.lpChainingStrategy?.target,
        existingContract?.["merklStrategy"] || contracts?.merklStrategy?.target,
        existingContract?.["kodiakIslandStrategy"] || contracts?.kodiakIslandStrategy?.target,
        existingContract?.["lpStrategyAerodrome"] || contracts?.lpStrategyAerodrome?.target,
        existingContract?.["farmingStrategy"] || contracts?.farmingStrategy?.target,
      ]?.filter(Boolean),
      networkConfig.swapRouters,
      [
        existingContract?.["vaultAutomator"] || contracts?.vaultAutomator?.target,
        existingContract?.["vaultAutomatorAerodrome"] || contracts?.vaultAutomatorAerodrome?.target,
        existingContract?.["merklAutomator"] || contracts?.merklAutomator?.target,
      ]?.filter(Boolean),
      commonConfig.signers,
      networkConfig.typedTokens || [],
      networkConfig.typedTokensTypes || [],
      commonConfig.vaultOwnerFeeBasisPoint,
      commonConfig.platformFeeBasisPoint,
      commonConfig.privatePlatformFeeBasisPoint,
      commonConfig.feeCollector,
      lpValidators,
      typedTokens,
      configs,
    );
  }

  if (networkConfig.lpValidator?.enabled) {
    await lpValidator?.lpValidator?.initialize(
      contractAdmin,
      existingContract?.["configManager"] || contracts?.configManager?.target,
      networkConfig.nfpmAddresses,
    );
  }

  if (networkConfig.lpValidatorAerodrome?.enabled) {
    await lpValidatorAerodrome?.lpValidatorAerodrome?.initialize(
      contractAdmin,
      existingContract?.["configManager"] || contracts?.configManager?.target,
      networkConfig?.aerodromeNfpmAddresses || [],
    );
  }

  return contracts;
}

export const deployVaultContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let vault;

  if (config.vault?.enabled) {
    vault = (await deployContract(
      `${step} >>`,
      config.vault?.autoVerifyContract,
      "Vault",
      existingContract?.["vault"],
      "contracts/public-vault/core/Vault.sol:Vault",
    )) as Vault;
  }

  return {
    vault,
  };
};

export const deployVaultAutomatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let vaultAutomator;

  if (config.vaultAutomator?.enabled) {
    vaultAutomator = (await deployContract(
      `${step} >>`,
      config.vaultAutomator?.autoVerifyContract,
      "contracts/public-vault/strategies/lpUniV3/VaultAutomator.sol:VaultAutomator",
      existingContract?.["vaultAutomator"],
      "contracts/public-vault/strategies/lpUniV3/VaultAutomator.sol:VaultAutomator",
      undefined,
      ["address", "address[]"],
      [contractAdmin, commonConfig.automationOperators],
    )) as VaultAutomator;
  }

  return {
    vaultAutomator,
  };
};

export const deployVaultAutomatorAerodromeContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let vaultAutomatorAerodrome;

  if (config.vaultAutomatorAerodrome?.enabled) {
    vaultAutomatorAerodrome = (await deployContract(
      `${step} >>`,
      config.vaultAutomatorAerodrome?.autoVerifyContract,
      "contracts/public-vault/strategies/lpAerodrome/VaultAutomator.sol:VaultAutomator",
      existingContract?.["vaultAutomatorAerodrome"],
      "contracts/public-vault/strategies/lpAerodrome/VaultAutomator.sol:VaultAutomator",
      undefined,
      ["address", "address[]"],
      [contractAdmin, commonConfig.automationOperators],
    )) as VaultAutomatorAerodrome;
  }

  return {
    vaultAutomatorAerodrome,
  };
};

export const deployMerklAutomatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let merklAutomator;

  if (config.merklAutomator?.enabled) {
    merklAutomator = (await deployContract(
      `${step} >>`,
      config.merklAutomator?.autoVerifyContract,
      "MerklAutomator",
      existingContract?.["merklAutomator"],
      "contracts/public-vault/strategies/merkl/MerklAutomator.sol:MerklAutomator",
      undefined,
      ["address", "address"],
      [contractAdmin, existingContract?.["configManager"] || contracts?.configManager?.target],
    )) as MerklAutomator;
  }
  return {
    merklAutomator,
  };
};

export const deployConfigManagerContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let configManager;

  if (config.configManager?.enabled) {
    configManager = (await deployContract(
      `${step} >>`,
      config.configManager?.autoVerifyContract,
      "ConfigManager",
      existingContract?.["configManager"],
      "contracts/public-vault/core/ConfigManager.sol:ConfigManager",
    )) as ConfigManager;
  }

  return {
    configManager,
  };
};

export const deployPoolOptimalSwapperContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let poolOptimalSwapper;
  if (config.poolOptimalSwapper?.enabled) {
    poolOptimalSwapper = (await deployContract(
      `${step} >>`,
      config.poolOptimalSwapper?.autoVerifyContract,
      "PoolOptimalSwapper",
      existingContract?.["poolOptimalSwapper"],
      "contracts/public-vault/core/PoolOptimalSwapper.sol:PoolOptimalSwapper",
    )) as PoolOptimalSwapper;
  }
  return {
    poolOptimalSwapper,
  };
};

export const deployKatanaPoolOptimalSwapperContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let katanaPoolOptimalSwapper;
  if (config.katanaPoolOptimalSwapper?.enabled) {
    katanaPoolOptimalSwapper = (await deployContract(
      `${step} >>`,
      config.katanaPoolOptimalSwapper?.autoVerifyContract,
      "KatanaPoolOptimalSwapper",
      existingContract?.["poolOptimalSwapper"],
      "contracts/public-vault/strategies/roninKatanaV3/KatanaPoolOptimalSwapper.sol:KatanaPoolOptimalSwapper",
      undefined,
      ["address"],
      [networkConfig?.katanaAggregateSwapRouter],
    )) as KatanaPoolOptimalSwapper;
  }
  return {
    poolOptimalSwapper: katanaPoolOptimalSwapper,
  };
};

export const deployLpFeeTakerContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpFeeTaker;
  if (config.lpFeeTaker?.enabled) {
    lpFeeTaker = (await deployContract(
      `${step} >>`,
      config.lpFeeTaker?.autoVerifyContract,
      "LpFeeTaker",
      existingContract?.["lpFeeTaker"],
      "contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol:LpFeeTaker",
    )) as LpFeeTaker;
  }
  return {
    lpFeeTaker,
  };
};

export const deployKatanaLpFeeTakerContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let katanaLpFeeTaker;
  if (config.katanaLpFeeTaker?.enabled) {
    katanaLpFeeTaker = (await deployContract(
      `${step} >>`,
      config.katanaLpFeeTaker?.autoVerifyContract,
      "KatanaLpFeeTaker",
      existingContract?.["lpFeeTaker"],
      "contracts/public-vault/strategies/roninKatanaV3/KatanaLpFeeTaker.sol:KatanaLpFeeTaker",
      undefined,
      ["address"],
      [networkConfig?.katanaAggregateSwapRouter],
    )) as KatanaLpFeeTaker;
  }
  return {
    lpFeeTaker: katanaLpFeeTaker,
  };
};

export const deployLpValidatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpValidator;

  if (config.lpValidator?.enabled) {
    lpValidator = (await deployContract(
      `${step} >>`,
      config.lpValidator?.autoVerifyContract,
      "LpValidator",
      existingContract?.["lpValidator"],
      "contracts/public-vault/strategies/lpUniV3/LpValidator.sol:LpValidator",
    )) as LpValidator;
  }

  return {
    lpValidator,
  };
};

export const deployLpValidatorAerodromeContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpValidatorAerodrome;

  if (config.lpValidatorAerodrome?.enabled) {
    lpValidatorAerodrome = (await deployContract(
      `${step} >>`,
      config.lpValidatorAerodrome?.autoVerifyContract,
      "contracts/public-vault/strategies/lpAerodrome/LpValidator.sol:LpValidator",
      existingContract?.["lpValidatorAerodrome"],
      "contracts/public-vault/strategies/lpAerodrome/LpValidator.sol:LpValidator",
    )) as LpValidatorAerodrome;
  }

  return {
    lpValidatorAerodrome,
  };
};

export const deployLpStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpStrategy;
  if (config.lpStrategy?.enabled) {
    lpStrategy = (await deployContract(
      `${step} >>`,
      config.lpStrategy?.autoVerifyContract,
      "contracts/public-vault/strategies/lpUniV3/LpStrategy.sol:LpStrategy",
      existingContract?.["lpStrategy"],
      "contracts/public-vault/strategies/lpUniV3/LpStrategy.sol:LpStrategy",
      undefined,
      ["address", "address", "address", "address"],
      [
        existingContract?.["configManager"] || contracts?.configManager?.target,
        existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
        existingContract?.["lpFeeTaker"] || contracts?.lpFeeTaker?.target,
      ],
    )) as LpStrategy;
  }
  return {
    lpStrategy,
  };
};

export const deployLpStrategyAerodromeContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpStrategyAerodrome;
  if (config.lpStrategyAerodrome?.enabled) {
    lpStrategyAerodrome = (await deployContract(
      `${step} >>`,
      config.lpStrategyAerodrome?.autoVerifyContract,
      "contracts/public-vault/strategies/lpAerodrome/LpStrategy.sol:LpStrategy",
      existingContract?.["lpStrategyAerodrome"],
      "contracts/public-vault/strategies/lpAerodrome/LpStrategy.sol:LpStrategy",
      undefined,
      ["address", "address", "address", "address"],
      [
        existingContract?.["configManager"] || contracts?.configManager?.target,
        existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
        existingContract?.["lpValidatorAerodrome"] || contracts?.lpValidatorAerodrome?.target,
        existingContract?.["lpFeeTaker"] || contracts?.lpFeeTaker?.target,
      ],
    )) as LpStrategyAerodrome;
  }
  return {
    lpStrategyAerodrome,
  };
};

export const deployLpChainingStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpChainingStrategy;
  if (config.lpChainingStrategy?.enabled) {
    lpChainingStrategy = (await deployContract(
      `${step} >>`,
      config.lpChainingStrategy?.autoVerifyContract,
      "LpChainingStrategy",
      existingContract?.["lpChainingStrategy"],
      "contracts/public-vault/strategies/lpChaining/LpChainingStrategy.sol:LpChainingStrategy",
      undefined,
      ["address"],
      [existingContract?.["configManager"] || contracts?.configManager?.target],
    )) as LpChainingStrategy;
  }
  return {
    lpChainingStrategy,
  };
};

export const deployMerklStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };
  let merklStrategy;
  if (config.merklStrategy?.enabled) {
    merklStrategy = (await deployContract(
      `${step} >>`,
      config.merklStrategy?.autoVerifyContract,
      "MerklStrategy",
      existingContract?.["merklStrategy"],
      "contracts/public-vault/strategies/merkl/MerklStrategy.sol:MerklStrategy",
      undefined,
      ["address"],
      [existingContract?.["configManager"] || contracts?.configManager?.target],
    )) as MerklStrategy;
  }
  return {
    merklStrategy,
  };
};

export const deployVaultFactoryContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let vaultFactory;
  if (config.vaultFactory?.enabled) {
    vaultFactory = (await deployContract(
      `${step} >>`,
      config.vaultFactory?.autoVerifyContract,
      "VaultFactory",
      existingContract?.["vaultFactory"],
      "contracts/public-vault/core/VaultFactory.sol:VaultFactory",
    )) as VaultFactory;
  }
  return {
    vaultFactory,
  };
};

export const deployKodiakIslandStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let kodiakIslandStrategy;
  if (config.kodiakIslandStrategy?.enabled) {
    kodiakIslandStrategy = (await deployContract(
      `${step} >>`,
      config.kodiakIslandStrategy?.autoVerifyContract,
      "KodiakIslandStrategy",
      existingContract?.["kodiakIslandStrategy"],
      "contracts/public-vault/strategies/kodiak/KodiakIslandStrategy.sol:KodiakIslandStrategy",
      undefined,
      ["address", "address", "address", "address", "address"],
      [
        existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
        networkConfig.rewardVaultFactory || "",
        existingContract?.["lpFeeTaker"] || contracts?.lpFeeTaker?.target,
        networkConfig.bgtToken || "",
        networkConfig.wbera || "",
      ],
    )) as KodiakIslandStrategy;
  }
  return {
    kodiakIslandStrategy,
  };
};

export const deployRewardSwapperContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let rewardSwapper;
  if (config.rewardSwapper?.enabled) {
    rewardSwapper = (await deployContract(
      `${step} >>`,
      config.rewardSwapper?.autoVerifyContract,
      "RewardSwapper",
      existingContract?.["rewardSwapper"],
      "contracts/public-vault/strategies/lpAerodrome/RewardSwapper.sol:RewardSwapper",
      undefined,
      ["address", "address", "address"],
      [
        existingContract?.["configManager"] || contracts?.configManager?.target,
        existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
        contractAdmin,
      ],
    )) as RewardSwapper;
  }
  return {
    rewardSwapper,
  };
};

export const deployFarmingStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let farmingStrategy;
  if (config.farmingStrategy?.enabled) {
    farmingStrategy = (await deployContract(
      `${step} >>`,
      config.farmingStrategy?.autoVerifyContract,
      "FarmingStrategy",
      existingContract?.["farmingStrategy"],
      "contracts/public-vault/strategies/lpAerodrome/FarmingStrategy.sol:FarmingStrategy",
      undefined,
      ["address", "address", "address"],
      [
        existingContract?.["lpStrategyAerodrome"] || contracts?.lpStrategyAerodrome?.target,
        existingContract?.["configManager"] || contracts?.configManager?.target,
        existingContract?.["rewardSwapper"] || contracts?.rewardSwapper?.target,
      ],
    )) as FarmingStrategy;
  }
  return {
    farmingStrategy,
  };
};

async function deployContract(
  step: number | string,
  autoVerify: boolean | undefined,
  contractName: string,
  contractAddress: string | undefined,
  contractLocation: string | undefined,
  customSalt?: string,
  argsTypes?: string[],
  args?: any[],
): Promise<BaseContract> {
  log(1, `${step}. Deploying '${contractName}'`);
  log(1, "------------------------------------");
  const factory = await ethers.getContractAt("ICreateX", createXContractAddress, await ethers.provider.getSigner());
  let contract;

  if (contractAddress) {
    log(2, `> contract already exists`);
    log(2, `> address:\t${contractAddress}`);
    // TODO: Transfer admin if needed
    contract = factory.attach(contractAddress);
  } else {
    let bytecode = (await ethers.getContractFactory(contractName)).bytecode;
    const encoder = new ethers.AbiCoder();
    if (!!argsTypes?.length && !!args?.length && argsTypes.length === args.length) {
      bytecode = solidityPacked(["bytes", "bytes"], [bytecode, encoder.encode(argsTypes || [], args)]);
    }
    const salt = encodeBytes32String((customSalt ? customSalt : SALT) || "");
    let deployTx;
    try {
      deployTx = await factory["deployCreate2(bytes32,bytes)"](salt, bytecode);
    } catch (e: any) {
      log(2, "failed to deploy contract", e);
    }
    const txHash = deployTx?.hash || "";
    await sleep(networkConfig.sleepTime ?? 60000);
    const txReceipt = await ethers.provider.getTransactionReceipt(txHash);
    const contractAddress =
      "0x" + txReceipt?.logs?.find((l) => l?.topics?.includes(createXTopic))?.topics?.[1]?.slice(26);
    contract = await ethers.getContractAt(contractName, contractAddress);
    await printInfo(deployTx);
    log(2, `> address:\t${contract.target}`);
  }

  // Only verify new contract to save time or Try to verify no matter what
  if (autoVerify) {
    // if (autoVerify) {
    try {
      log(3, ">> sleep first, wait for contract data to be propagated");
      await sleep(networkConfig.sleepTime ?? 60000);
      log(3, ">> start verifying");
      if (isRonin) {
        await run("verify:sourcify", {
          address: contract.target,
          constructorArguments: args,
          contract: contractLocation,
        });
      } else {
        if (!!contractLocation) {
          await run("verify:verify", {
            address: contract.target,
            constructorArguments: args,
            contract: contractLocation,
          });
        } else {
          await run("verify:verify", {
            address: contract.target,
            constructorArguments: args,
          });
        }
      }
      log(3, ">> done verifying");
    } catch (e) {
      log(2, "failed to verify contract", e);
    }
  }

  return contract;
}

async function printInfo(tx: any) {
  if (!tx) {
    log(5, `> tx is undefined`);
    return;
  }
  const receipt = await tx.wait(1);

  log(5, `> tx hash:\t${tx.hash}`);
  log(5, `> gas price:\t${tx.gasPrice?.toString()}`);
  log(5, `> gas used:\t${!!receipt && receipt.gasUsed.toString()}`);
}

export function convertToAddressObject(obj: Record<string, any> | Array<any> | BaseContract): any {
  if (obj === undefined) return obj;
  if (obj instanceof BaseContract) {
    return obj.target;
  } else if (isArray(obj)) {
    return obj.map((k) => convertToAddressObject(k));
  } else if (typeof obj == "string") {
    return obj;
  } else {
    let ret = {};
    for (let k in obj) {
      // @ts-ignore
      ret[k] = convertToAddressObject(obj[k]);
    }
    return ret;
  }
}

let prevLevel: number;
function log(level: number, ...args: any[]) {
  if (prevLevel != undefined && prevLevel > level) {
    console.log("\n");
  }
  prevLevel = level;

  let prefix = "";
  for (let i = 0; i < level; i++) {
    prefix += "    ";
  }
  console.log(`${prefix}`, ...args);
}
