import { ethers, network, run } from "hardhat";
import { NetworkConfig } from "../configs/networkConfig";
import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { IConfig } from "../configs/interfaces";
import { sleep } from "./helpers";
import { isArray } from "lodash";
import {
  PrivateVault,
  PrivateVaultFactory,
  PrivateConfigManager,
} from "../typechain-types/contracts/private-vault/core";
import { PrivateVaultAutomator } from "../typechain-types";
import { AerodromeFarmingStrategy } from "../typechain-types/contracts/private-vault/strategies/farm/AerodromeFarmingStrategy";
import { V3UtilsStrategy } from "../typechain-types/contracts/private-vault/strategies/lpv3/V3UtilsStrategy";
import { V4UtilsStrategy } from "../typechain-types/contracts/private-vault/strategies/lpv4/V4UtilsStrategy";
import { commonConfig } from "../configs/config_common";

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

export interface PrivateContracts {
  privateVault?: PrivateVault;
  privateVaultFactory?: PrivateVaultFactory;
  privateConfigManager?: PrivateConfigManager;
  privateVaultAutomator?: PrivateVaultAutomator;
  aerodromeFarmingStrategy?: AerodromeFarmingStrategy;
  v3UtilsStrategy?: V3UtilsStrategy;
  v4UtilsStrategy?: V4UtilsStrategy;
}

export const deploy = async (
  existingContract: Record<string, any> | undefined = undefined,
): Promise<PrivateContracts> => {
  const [deployer] = await ethers.getSigners();

  const deployerAddress = await deployer.getAddress();

  log(0, "Start deploying private vault contracts");
  log(0, "=====================================\n");

  let deployedContracts = await deployContracts(existingContract);

  // Summary
  log(0, "Summary");
  log(0, "=======\n");

  log(0, JSON.stringify(convertToAddressObject(deployedContracts), null, 2));

  console.log("\nPrivate vault deployment complete!");
  return deployedContracts;
};

async function deployContracts(
  existingContract: Record<string, any> | undefined = undefined,
): Promise<PrivateContracts> {
  let step = 0;

  const privateVault = await deployPrivateVaultContract(++step, existingContract);
  const privateVaultFactory = await deployPrivateVaultFactoryContract(++step, existingContract);
  const privateConfigManager = await deployPrivateConfigManagerContract(++step, existingContract);
  const privateVaultAutomator = await deployPrivateVaultAutomatorContract(++step, existingContract);
  const aerodromeFarmingStrategy = await deployAerodromeFarmingStrategyContract(++step, existingContract);
  const v3UtilsStrategy = await deployV3UtilsStrategyContract(++step, existingContract);
  const v4UtilsStrategy = await deployV4UtilsStrategyContract(++step, existingContract);

  const contracts: PrivateContracts = {
    privateVault: privateVault.privateVault,
    privateVaultFactory: privateVaultFactory.privateVaultFactory,
    privateConfigManager: privateConfigManager.privateConfigManager,
    privateVaultAutomator: privateVaultAutomator.privateVaultAutomator,
    aerodromeFarmingStrategy: aerodromeFarmingStrategy.aerodromeFarmingStrategy,
    v3UtilsStrategy: v3UtilsStrategy.v3UtilsStrategy,
    v4UtilsStrategy: v4UtilsStrategy.v4UtilsStrategy,
  };

  // Initialize contracts
  if (networkConfig.privateVaultFactory?.enabled) {
    await privateVaultFactory?.privateVaultFactory?.initialize(
      contractAdmin,
      existingContract?.["privateConfigManager"] || contracts?.privateConfigManager?.target,
      existingContract?.["privateVault"] || contracts?.privateVault?.target,
    );
  }

  if (networkConfig.privateConfigManager?.enabled) {
    // Configure whitelistedCaller (PrivateVaultAutomator) and whitelistedTargets (AerodromeFarmingStrategy, V3UtilsStrategy, V4UtilsStrategy)
    const whitelistedCallers = [
      existingContract?.["privateVaultAutomator"] || contracts?.privateVaultAutomator?.target,
    ].filter(Boolean);

    const whitelistedTargets = [
      existingContract?.["aerodromeFarmingStrategy"] || contracts?.aerodromeFarmingStrategy?.target,
      existingContract?.["v3UtilsStrategy"] || contracts?.v3UtilsStrategy?.target,
      existingContract?.["v4UtilsStrategy"] || contracts?.v4UtilsStrategy?.target,
    ].filter(Boolean);

    await privateConfigManager?.privateConfigManager?.initialize(contractAdmin, whitelistedTargets, whitelistedCallers);
  }

  return contracts;
}

export const deployPrivateVaultContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let privateVault;

  if (config.privateVault?.enabled) {
    privateVault = (await deployContract(
      `${step} >>`,
      config.privateVault?.autoVerifyContract,
      "PrivateVault",
      existingContract?.["privateVault"],
      "contracts/private-vault/core/PrivateVault.sol:PrivateVault",
    )) as PrivateVault;
  }

  return {
    privateVault,
  };
};

export const deployPrivateVaultFactoryContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let privateVaultFactory;

  if (config.privateVaultFactory?.enabled) {
    privateVaultFactory = (await deployContract(
      `${step} >>`,
      config.privateVaultFactory?.autoVerifyContract,
      "PrivateVaultFactory",
      existingContract?.["privateVaultFactory"],
      "contracts/private-vault/core/PrivateVaultFactory.sol:PrivateVaultFactory",
    )) as PrivateVaultFactory;
  }

  return {
    privateVaultFactory,
  };
};

export const deployPrivateConfigManagerContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let privateConfigManager;

  if (config.privateConfigManager?.enabled) {
    privateConfigManager = (await deployContract(
      `${step} >>`,
      config.privateConfigManager?.autoVerifyContract,
      "PrivateConfigManager",
      existingContract?.["privateConfigManager"],
      "contracts/private-vault/core/PrivateConfigManager.sol:PrivateConfigManager",
    )) as PrivateConfigManager;
  }

  return {
    privateConfigManager,
  };
};

export const deployPrivateVaultAutomatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let privateVaultAutomator;

  if (config.privateVaultAutomator?.enabled) {
    privateVaultAutomator = (await deployContract(
      `${step} >>`,
      config.privateVaultAutomator?.autoVerifyContract,
      "PrivateVaultAutomator",
      existingContract?.["privateVaultAutomator"],
      "contracts/private-vault/core/PrivateVaultAutomator.sol:PrivateVaultAutomator",
      undefined,
      ["address", "address[]"],
      [contractAdmin, commonConfig.automationOperators],
    )) as PrivateVaultAutomator;
  }

  return {
    privateVaultAutomator,
  };
};

export const deployAerodromeFarmingStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let aerodromeFarmingStrategy;

  if (config.privateAerodromeFarmingStrategy?.enabled) {
    aerodromeFarmingStrategy = (await deployContract(
      `${step} >>`,
      config.privateAerodromeFarmingStrategy?.autoVerifyContract,
      "AerodromeFarmingStrategy",
      existingContract?.["aerodromeFarmingStrategy"],
      "contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol:AerodromeFarmingStrategy",
      undefined,
      ["address"],
      [config.aerodromeGaugeFactory],
    )) as AerodromeFarmingStrategy;
  }

  return {
    aerodromeFarmingStrategy,
  };
};

export const deployPancakeV3FarmingStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let aerodromeFarmingStrategy;

  if (config.privateAerodromeFarmingStrategy?.enabled) {
    aerodromeFarmingStrategy = (await deployContract(
      `${step} >>`,
      config.privatePancakeV3FarmingStrategy?.autoVerifyContract,
      "PancakeV3FarmingStrategy",
      existingContract?.["pancakeV3FarmingStrategy"],
      "contracts/private-vault/strategies/farm/PancakeV3FarmingStrategy.sol:PancakeV3FarmingStrategy",
      undefined,
      ["address"],
      [config.pancakeV3MasterChef],
    )) as AerodromeFarmingStrategy;
  }

  return {
    aerodromeFarmingStrategy,
  };
};

export const deployV3UtilsStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let v3UtilsStrategy;

  if (config.privateV3UtilsStrategy?.enabled) {
    v3UtilsStrategy = (await deployContract(
      `${step} >>`,
      config.privateV3UtilsStrategy?.autoVerifyContract,
      "V3UtilsStrategy",
      existingContract?.["v3UtilsStrategy"],
      "contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol:V3UtilsStrategy",
      undefined,
      ["address"],
      [config.v3UtilsAddress],
    )) as V3UtilsStrategy;
  }

  return {
    v3UtilsStrategy,
  };
};

export const deployV4UtilsStrategyContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  customNetworkConfig?: IConfig,
): Promise<PrivateContracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let v4UtilsStrategy;

  if (config.privateV4UtilsStrategy?.enabled) {
    v4UtilsStrategy = (await deployContract(
      `${step} >>`,
      config.privateV4UtilsStrategy?.autoVerifyContract,
      "V4UtilsStrategy",
      existingContract?.["v4UtilsStrategy"],
      "contracts/private-vault/strategies/lpv4/V4UtilsStrategy.sol:V4UtilsStrategy",
      undefined,
      ["address"],
      [config.v4UtilsAddress],
    )) as V4UtilsStrategy;
  }

  return {
    v4UtilsStrategy,
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
