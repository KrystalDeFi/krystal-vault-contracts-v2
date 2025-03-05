import { ethers, network, run } from "hardhat";
import { NetworkConfig } from "../configs/networkConfig";
import { KrystalVault, KrystalVaultFactory, PoolOptimalSwapper, KrystalVaultAutomator } from "../typechain-types";
import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { IConfig } from "../configs/interfaces";
import { sleep } from "./helpers";
import { last } from "lodash";

const { SALT } = process.env;
const createXContractAddress = "0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed";

const networkConfig = NetworkConfig[network.name];
if (!networkConfig) {
  throw new Error(`Missing deploy config for ${network.name}`);
}

export interface Contracts {
  poolOptimalSwapper?: PoolOptimalSwapper;
  krystalVault?: KrystalVault;
  krystalVaultFactory?: KrystalVaultFactory;
  krystalVaultAutomator?: KrystalVaultAutomator;
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

  const poolOptimalSwapper = await deployPoolOptimalSwapperContract(++step, existingContract, deployer);
  const krystalVault = await deployKrystalVaultContract(++step, existingContract, deployer);
  const krystalVaultAutomator = await deployKrystalVaultAutomatorContract(++step, existingContract, deployer);

  const contracts: Contracts = {
    poolOptimalSwapper: poolOptimalSwapper.poolOptimalSwapper,
    krystalVault: krystalVault.krystalVault,
    krystalVaultAutomator: krystalVaultAutomator.krystalVaultAutomator,
  };

  contracts.krystalVaultFactory = (
    await deployKrystalVaultFactoryContract(++step, existingContract, deployer, undefined, contracts)
  ).krystalVaultFactory;

  return contracts;
}

export const deployPoolOptimalSwapperContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let poolOptimalSwapper;
  if (config.poolOptimalSwapper?.enabled) {
    poolOptimalSwapper = (await deployContract(
      `${step} >>`,
      config.poolOptimalSwapper?.autoVerifyContract,
      "PoolOptimalSwapper",
      existingContract?.["PoolOptimalSwapper"],
      "contracts/PoolOptimalSwapper.sol:PoolOptimalSwapper",
    )) as PoolOptimalSwapper;
  }
  return {
    poolOptimalSwapper,
  };
};

export const deployKrystalVaultContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let krystalVault;
  if (config.krystalVault?.enabled) {
    krystalVault = (await deployContract(
      `${step} >>`,
      config.krystalVault?.autoVerifyContract,
      "KrystalVault",
      existingContract?.["krystalVault"],
      "contracts/KrystalVault.sol:KrystalVault",
    )) as KrystalVault;
  }
  return {
    krystalVault,
  };
};

export const deployKrystalVaultFactoryContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let krystalVaultFactory;
  if (config.krystalVaultFactory?.enabled) {
    krystalVaultFactory = (await deployContract(
      `${step} >>`,
      config.krystalVaultFactory?.autoVerifyContract,
      "KrystalVaultFactory",
      existingContract?.["krystalVaultFactory"],
      "contracts/KrystalVaultFactory.sol:KrystalVaultFactory",
      ["address", "address", "address", "address", "address", "uint16"],
      [
        config.uniswapV3Factory,
        existingContract?.["krystalVault"] || contracts?.krystalVault?.target,
        existingContract?.["krystalVaultAutomator"] || contracts?.krystalVaultAutomator?.target,
        existingContract?.["poolOptimalSwapper"] || contracts?.poolOptimalSwapper?.target,
        config.platformFeeRecipient,
        config.platformFeeBasisPoint,
      ],
    )) as KrystalVaultFactory;
  }
  return {
    krystalVaultFactory,
  };
};

export const deployKrystalVaultAutomatorContract = async (
  step: number,
  existingContract: Record<string, any> | undefined,
  deployer: string,
  customNetworkConfig?: IConfig,
  contracts?: Contracts,
): Promise<Contracts> => {
  const config = { ...networkConfig, ...customNetworkConfig };

  let krystalVaultAutomator;
  if (config.krystalVaultAutomator?.enabled) {
    krystalVaultAutomator = (await deployContract(
      `${step} >>`,
      config.krystalVaultAutomator?.autoVerifyContract,
      "KrystalVaultAutomator",
      existingContract?.["krystalVaultAutomator"],
      "contracts/KrystalVaultAutomator.sol:KrystalVaultAutomator",
      ["address"],
      [deployer],
    )) as KrystalVaultAutomator;
  }
  return {
    krystalVaultAutomator,
  };
};

async function deployContract(
  step: number | string,
  autoVerify: boolean | undefined,
  contractName: string,
  contractAddress: string | undefined,
  contractLocation: string | undefined,
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
    const salt = encodeBytes32String(SALT || "");
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
