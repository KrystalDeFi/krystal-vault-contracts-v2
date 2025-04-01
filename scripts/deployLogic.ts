import { ethers, network, run } from "hardhat";
import { NetworkConfig } from "../configs/networkConfig";
import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { IConfig } from "../configs/interfaces";
import { sleep } from "./helpers";
import { isArray, last } from "lodash";
import { PoolOptimalSwapper, Vault, VaultFactory, ConfigManager } from "../typechain-types/contracts/core";
import {
  LpStrategy,
  VaultAutomator as LpUniV3VaultAutomator,
  LpValidator,
} from "../typechain-types/contracts/strategies/lpUniV3";

const { SALT } = process.env;
const createXContractAddress = "0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed";

const networkConfig = NetworkConfig[network.name];
if (!networkConfig) {
  throw new Error(`Missing deploy config for ${network.name}`);
}

export interface Contracts {
  vault?: Vault;
  vaultAutomator?: any[];
  configManager?: ConfigManager;
  poolOptimalSwapper?: PoolOptimalSwapper;
  lpValidator?: LpValidator;
  lpStrategy?: LpStrategy;
  vaultFactory?: VaultFactory;
}

export const deploy = async (existingContract: Record<string, any> | undefined = undefined): Promise<Contracts> => {
  const [deployer] = await ethers.getSigners();

  const deployerAddress = await deployer.getAddress();

  log(0, "Start deployin contracts");
  log(0, "======================\n");

  let deployedContracts = await deployContracts(existingContract, deployerAddress);

  // Summary
  log(0, "Summary");
  log(0, "=======\n");

  log(0, JSON.stringify(convertToAddressObject(deployedContracts), null, 2));

  console.log("\nDeployment complete!");
  return deployedContracts;
};

async function deployContracts(
  existingContract: Record<string, any> | undefined = undefined,
  deployer: string,
): Promise<Contracts> {
  let step = 0;

  const vault = await deployVaultContract(++step, existingContract, deployer);
  const vaultAutomator = await deployVaultAutomatorContract(++step, existingContract, deployer);
  const poolOptimalSwapper = await deployPoolOptimalSwapperContract(++step, existingContract, deployer);

  const contracts: Contracts = {
    vault: vault.vault,
    vaultAutomator: vaultAutomator.vaultAutomator,
    poolOptimalSwapper: poolOptimalSwapper.poolOptimalSwapper,
  };

  const configManager = await deployConfigManagerContract(++step, existingContract, deployer, undefined, contracts);

  Object.assign(contracts, {
    configManager: configManager.configManager,
  });

  const lpValidator = await deployLpValidatorContract(++step, existingContract, deployer, undefined, contracts);

  Object.assign(contracts, {
    lpValidator: lpValidator.lpValidator,
  });

  const lpStrategy = await deployLpStrategyContract(++step, existingContract, deployer, undefined, contracts);
  const vaultFactory = await deployVaultFactoryContract(++step, existingContract, deployer, undefined, contracts);

  Object.assign(contracts, {
    lpStrategy: lpStrategy.lpStrategy,
    vaultFactory: vaultFactory.vaultFactory,
  });

  return contracts;
}

export const deployVaultContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
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
      "contracts/core/Vault.sol:Vault",
    )) as Vault;
  }

  return {
    vault,
  };
};

export const deployVaultAutomatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let vaultAutomators: any[] = [];

  if (config.vaultAutomator?.enabled) {
    vaultAutomators.push(
      (await deployContract(
        `${step} >>`,
        config.vaultAutomator?.autoVerifyContract,
        "VaultAutomator",
        existingContract?.["vaultAutomator"]?.[0],
        "contracts/strategies/lpUniV3/VaultAutomator.sol:VaultAutomator",
        undefined,
        ["address"],
        [deployer],
      )) as LpUniV3VaultAutomator,
    );
  }

  return {
    vaultAutomator: vaultAutomators,
  };
};

export const deployConfigManagerContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
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
      "contracts/core/ConfigManager.sol:ConfigManager",
      undefined,
      ["address", "address[]", "address[]", "uint256[]"],
      [
        deployer,
        existingContract?.["vaultAutomator"] || contracts?.vaultAutomator?.map((c) => c?.target),
        config.typedTokens,
        config.typedTokensTypes,
      ],
    )) as ConfigManager;
  }
  return {
    configManager,
  };
};

export const deployPoolOptimalSwapperContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
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
      "contracts/core/PoolOptimalSwapper.sol:PoolOptimalSwapper",
    )) as PoolOptimalSwapper;
  }
  return {
    poolOptimalSwapper,
  };
};

export const deployLpValidatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
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
      "contracts/strategies/lpUniV3/LpValidator.sol:LpValidator",
      undefined,
      ["address"],
      [existingContract?.["configManager"] || contracts?.configManager?.target],
    )) as LpValidator;
  }
  return {
    lpValidator,
  };
};

export const deployLpStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpStrategy;
  if (config.lpStrategy?.enabled) {
    lpStrategy = (await deployContract(
      `${step} >>`,
      config.lpStrategy?.autoVerifyContract,
      "LpStrategy",
      existingContract?.["lpStrategy"],
      "contracts/strategies/lpUniV3/LpStrategy.sol:LpStrategy",
      undefined,
      ["address", "address"],
      [
        existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
        existingContract?.["lpValidator"] || contracts?.lpValidator?.target,
      ],
    )) as LpStrategy;
  }
  return {
    lpStrategy,
  };
};

export const deployVaultFactoryContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
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
      "contracts/core/VaultFactory.sol:VaultFactory",
      undefined,
      ["address", "address", "address", "address"],
      [
        deployer,
        config.wrapToken,
        existingContract?.["configManager"] || contracts?.configManager?.target,
        existingContract?.["vault"] || contracts?.vault?.target,
      ],
    )) as VaultFactory;
  }
  return {
    vaultFactory,
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
    const txReceipt = await ethers.provider.getTransactionReceipt(txHash);
    const contractAddress = "0x" + last(txReceipt?.logs)?.topics?.[1]?.slice(26);
    contract = await ethers.getContractAt(contractName, contractAddress);
    await printInfo(deployTx);
    log(2, `> address:\t${contract.target}`);
  }

  // Only verify new contract to save time or Try to verify no matter what
  if (autoVerify && !contractAddress) {
    // if (autoVerify) {
    try {
      log(3, ">> sleep first, wait for contract data to be propagated");
      await sleep(networkConfig.sleepTime ?? 60000);
      log(3, ">> start verifying");
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
