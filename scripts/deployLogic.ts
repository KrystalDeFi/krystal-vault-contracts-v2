import { ethers, network, run } from "hardhat";
import { NetworkConfig } from "../configs/networkConfig";
import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { IConfig } from "../configs/interfaces";
import { sleep } from "./helpers";
import { last } from "lodash";
import {
  LpStrategy,
  PoolOptimalSwapper,
  Vault,
  VaultAutomator,
  VaultFactory,
  VaultZapper,
  ConfigManager,
} from "../typechain-types";

const { SALT } = process.env;
const createXContractAddress = "0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed";

const networkConfig = NetworkConfig[network.name];
if (!networkConfig) {
  throw new Error(`Missing deploy config for ${network.name}`);
}

export interface Contracts {
  vault?: Vault;
  vaultAutomator?: VaultAutomator;
  vaultZapper?: VaultZapper;
  configManager?: ConfigManager;
  poolOptimalSwapper?: PoolOptimalSwapper;
  lpStrategy?: Record<string, LpStrategy>;
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
  const vaultZapper = await deployVaultZapperContract(++step, existingContract, deployer);
  const configManager = await deployConfigManagerContract(++step, existingContract, deployer);
  const poolOptimalSwapper = await deployPoolOptimalSwapperContract(++step, existingContract, deployer);

  const contracts: Contracts = {
    vault: vault.vault,
    vaultAutomator: vaultAutomator.vaultAutomator,
    vaultZapper: vaultZapper.vaultZapper,
    configManager: configManager.configManager,
    poolOptimalSwapper: poolOptimalSwapper.poolOptimalSwapper,
  };

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

  let vaultAutomator;

  if (config.vaultAutomator?.enabled) {
    vaultAutomator = (await deployContract(
      `${step} >>`,
      config.vaultAutomator?.autoVerifyContract,
      "VaultAutomator",
      existingContract?.["vaultAutomator"],
      "contracts/core/VaultAutomator.sol:VaultAutomator",
    )) as VaultAutomator;
  }

  return {
    vaultAutomator,
  };
};

export const deployVaultZapperContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let vaultZapper;

  if (config.vaultZapper?.enabled) {
    vaultZapper = (await deployContract(
      `${step} >>`,
      config.vaultZapper?.autoVerifyContract,
      "VaultZapper",
      existingContract?.["vaultZapper"],
      "contracts/core/VaultZapper.sol:VaultZapper",
    )) as VaultZapper;
  }

  return {
    vaultZapper,
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
      ["address[]"],
      [config.lpStrategyPrincipalTokens?.slice(1)],
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

export const deployLpStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let lpStrategy: Record<string, LpStrategy> = {};
  if (config.lpStrategy?.enabled) {
    config.lpStrategyPrincipalTokens?.forEach(async (token: string) => {
      const lpStrategy = (await deployContract(
        `${step} >>`,
        config.lpStrategy?.autoVerifyContract,
        "LpStrategy",
        existingContract?.["lpStrategy"]?.[token],
        "contracts/strategies/lp/LpStrategy.sol:LpStrategy",
        `${SALT}_${token}`,
        ["address", "address", "address"],
        [
          token,
          existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
          existingContract?.["configManager"] || contracts?.configManager?.target,
        ],
      )) as LpStrategy;

      Object.assign(lpStrategy, { token });
    });
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
      ["address", "address", "address", "address", "address", "uint16"],
      [
        config.lpStrategyPrincipalTokens?.[0],
        existingContract?.["configManager"] || contracts?.configManager?.target,
        existingContract?.["vault"] || contracts?.vault?.target,
        existingContract?.["vaultAutomator"] || contracts?.vaultAutomator?.target,
        config.platformFeeRecipient,
        config.platformFeeBasisPoint,
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
    const salt = encodeBytes32String((customSalt ?? SALT) || "");
    const deployTx = await factory["deployCreate2(bytes32,bytes)"](salt, bytecode);
    const txHash = deployTx.hash;
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
  } else if (Array.isArray(obj)) {
    return obj.map((k) => convertToAddressObject(obj[k]));
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
