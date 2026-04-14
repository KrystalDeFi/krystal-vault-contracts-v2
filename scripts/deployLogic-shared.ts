import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { ethers, network, run } from "hardhat";
import { isArray } from "lodash";
import { commonConfig } from "../configs/config_common";
import { NetworkConfig } from "../configs/networkConfig";
import { sleep } from "./helpers";
import type {
  SharedConfigManager,
  SharedVault,
  SharedVaultAutomator,
  SharedVaultFactory,
  SharedVaultGateway,
} from "../typechain-types/contracts/shared-vault/core";
import type {
  SharedAerodromeStrategy,
  SharedPancakeV3Strategy,
  SharedV3Strategy,
} from "../typechain-types/contracts/shared-vault/strategies";
import type { SharedV4Strategy } from "../typechain-types/contracts/shared-vault/strategies/SharedV4Strategy.sol";

const { SALT } = process.env;

const createXContractAddress = "0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed";
const createXTopic = "0xb8fda7e00c6b06a2b54e58521bc5894fee35f1090e5a3bb6390bfe2b98b497f7";

const isRonin = network.name === "ronin_mainnet";
const isHyperevm = network.name === "hyperevm_mainnet";
const contractAdmin = isRonin ? commonConfig.roninAdmin : isHyperevm ? commonConfig.hyperevmAdmin : commonConfig.admin;

const networkConfig = NetworkConfig[network.name];
if (!networkConfig) {
  throw new Error(`Missing deploy config for ${network.name}`);
}

export interface SharedContracts {
  sharedVault?: SharedVault;
  sharedVaultFactory?: SharedVaultFactory;
  sharedConfigManager?: SharedConfigManager;
  sharedVaultAutomator?: SharedVaultAutomator;
  sharedVaultGateway?: SharedVaultGateway;
  sharedV3Strategy?: SharedV3Strategy;
  sharedV4Strategy?: SharedV4Strategy;
  sharedAerodromeStrategy?: SharedAerodromeStrategy;
  sharedPancakeV3Strategy?: SharedPancakeV3Strategy;
}

export const deploy = async (
  existingContract: Record<string, any> | undefined = undefined,
): Promise<SharedContracts> => {
  log(0, "Start deploying shared vault contracts");
  log(0, "=====================================\n");

  let deployedContracts = await deployContracts(existingContract);

  log(0, "Summary");
  log(0, "=======\n");
  log(0, JSON.stringify(convertToAddressObject(deployedContracts), null, 2));

  console.log("\nShared vault deployment complete!");
  return deployedContracts;
};

async function deployContracts(
  existingContract: Record<string, any> | undefined = undefined,
): Promise<SharedContracts> {
  let step = 0;

  const contracts: SharedContracts = {};

  const lpFeeTakerAddress: string | undefined = existingContract?.["lpFeeTaker"];

  // 1. Deploy SharedConfigManager
  if (networkConfig.sharedConfigManager?.enabled) {
    contracts.sharedConfigManager = (await deployContract(
      ++step,
      networkConfig.sharedConfigManager?.autoVerifyContract,
      "SharedConfigManager",
      existingContract?.["sharedConfigManager"],
      "contracts/shared-vault/core/SharedConfigManager.sol:SharedConfigManager",
    )) as SharedConfigManager;
  }

  // 2. Deploy SharedVault implementation
  if (networkConfig.sharedVault?.enabled) {
    contracts.sharedVault = (await deployContract(
      ++step,
      networkConfig.sharedVault?.autoVerifyContract,
      "SharedVault",
      existingContract?.["sharedVault"],
      "contracts/shared-vault/core/SharedVault.sol:SharedVault",
    )) as SharedVault;
  }

  // 3. Deploy SharedVaultFactory
  if (networkConfig.sharedVaultFactory?.enabled) {
    contracts.sharedVaultFactory = (await deployContract(
      ++step,
      networkConfig.sharedVaultFactory?.autoVerifyContract,
      "SharedVaultFactory",
      existingContract?.["sharedVaultFactory"],
      "contracts/shared-vault/core/SharedVaultFactory.sol:SharedVaultFactory",
    )) as SharedVaultFactory;
  }

  // 4. Deploy SharedV3Strategy
  if (networkConfig.sharedV3Strategy?.enabled) {
    contracts.sharedV3Strategy = (await deployContract(
      ++step,
      networkConfig.sharedV3Strategy?.autoVerifyContract,
      "SharedV3Strategy",
      existingContract?.["sharedV3Strategy"],
      "contracts/shared-vault/strategies/SharedV3Strategy.sol:SharedV3Strategy",
      undefined,
      ["address", "address"],
      [networkConfig.v3UtilsAddress, lpFeeTakerAddress],
    )) as SharedV3Strategy;
  }

  // 5. Deploy SharedV4Strategy
  if (networkConfig.sharedV4Strategy?.enabled) {
    contracts.sharedV4Strategy = (await deployContract(
      ++step,
      networkConfig.sharedV4Strategy?.autoVerifyContract,
      "SharedV4Strategy",
      existingContract?.["sharedV4Strategy"],
      "contracts/shared-vault/strategies/SharedV4Strategy.sol:SharedV4Strategy",
      undefined,
      ["address"],
      [networkConfig.v4UtilsAddress],
    )) as SharedV4Strategy;
  }

  // 6. Deploy SharedAerodromeStrategy
  if (networkConfig.sharedAerodromeStrategy?.enabled) {
    contracts.sharedAerodromeStrategy = (await deployContract(
      ++step,
      networkConfig.sharedAerodromeStrategy?.autoVerifyContract,
      "SharedAerodromeStrategy",
      existingContract?.["sharedAerodromeStrategy"],
      "contracts/shared-vault/strategies/SharedAerodromeStrategy.sol:SharedAerodromeStrategy",
      undefined,
      ["address", "address", "address", "address"],
      [
        networkConfig.v3UtilsAddress,
        lpFeeTakerAddress,
        networkConfig.aerodromeGaugeFactory,
        existingContract?.["sharedConfigManager"] || contracts.sharedConfigManager?.target,
      ],
    )) as SharedAerodromeStrategy;
  }

  // 7. Deploy SharedPancakeV3Strategy
  if (networkConfig.sharedPancakeV3Strategy?.enabled) {
    contracts.sharedPancakeV3Strategy = (await deployContract(
      ++step,
      networkConfig.sharedPancakeV3Strategy?.autoVerifyContract,
      "SharedPancakeV3Strategy",
      existingContract?.["sharedPancakeV3Strategy"],
      "contracts/shared-vault/strategies/SharedPancakeV3Strategy.sol:SharedPancakeV3Strategy",
      undefined,
      ["address", "address", "address", "address"],
      [
        networkConfig.v3UtilsAddress,
        lpFeeTakerAddress,
        networkConfig.pancakeV3MasterChef,
        existingContract?.["sharedConfigManager"] || contracts.sharedConfigManager?.target,
      ],
    )) as SharedPancakeV3Strategy;
  }

  // 8. Deploy SharedVaultAutomator
  if (networkConfig.sharedVaultAutomator?.enabled) {
    contracts.sharedVaultAutomator = (await deployContract(
      ++step,
      networkConfig.sharedVaultAutomator?.autoVerifyContract,
      "SharedVaultAutomator",
      existingContract?.["sharedVaultAutomator"],
      "contracts/shared-vault/core/SharedVaultAutomator.sol:SharedVaultAutomator",
      undefined,
      ["address", "address[]"],
      [contractAdmin, commonConfig.automationOperators],
    )) as SharedVaultAutomator;
  }

  // 9. Deploy SharedVaultGateway (upgradeable: no constructor; `initialize` sets owner, swap router, WETH)
  if (networkConfig.sharedVaultGateway?.enabled) {
    const gatewaySwapRouter = networkConfig.sharedVaultGateway.swapRouter ?? networkConfig.swapRouters?.[0];
    if (gatewaySwapRouter == null || gatewaySwapRouter === "") {
      throw new Error(
        "sharedVaultGateway: set `sharedVaultGateway.swapRouter` or at least one `swapRouters` entry on the network config",
      );
    }
    if (!networkConfig.wrapToken) {
      throw new Error("sharedVaultGateway: `wrapToken` is required on the network config");
    }

    const existingGateway = existingContract?.["sharedVaultGateway"];
    contracts.sharedVaultGateway = (await deployContract(
      ++step,
      networkConfig.sharedVaultGateway.autoVerifyContract,
      "SharedVaultGateway",
      existingGateway,
      "contracts/shared-vault/core/SharedVaultGateway.sol:SharedVaultGateway",
    )) as SharedVaultGateway;

    if (!existingGateway) {
      await contracts.sharedVaultGateway.initialize(contractAdmin, gatewaySwapRouter, networkConfig.wrapToken);
    }
  }

  // Initialize SharedVaultFactory
  if (networkConfig.sharedVaultFactory?.enabled) {
    await contracts.sharedVaultFactory?.initialize(
      contractAdmin,
      existingContract?.["sharedConfigManager"] || contracts.sharedConfigManager?.target,
      existingContract?.["sharedVault"] || contracts.sharedVault?.target,
      networkConfig.wrapToken!,
    );
  }

  // Initialize SharedConfigManager
  if (networkConfig.sharedConfigManager?.enabled) {
    const whitelistedTargets = [
      existingContract?.["sharedV3Strategy"] || contracts.sharedV3Strategy?.target,
      existingContract?.["sharedV4Strategy"] || contracts.sharedV4Strategy?.target,
      existingContract?.["sharedAerodromeStrategy"] || contracts.sharedAerodromeStrategy?.target,
      existingContract?.["sharedPancakeV3Strategy"] || contracts.sharedPancakeV3Strategy?.target,
    ].filter(Boolean) as string[];

    const whitelistedCallers = [
      existingContract?.["sharedVaultAutomator"] || contracts.sharedVaultAutomator?.target,
    ].filter(Boolean) as string[];

    const whitelistedNfpms = (networkConfig.nfpmAddresses ?? []) as string[];
    const whitelistedSwapRouters = (networkConfig.swapRouters ?? []) as string[];

    await contracts.sharedConfigManager?.initialize(
      contractAdmin,
      whitelistedTargets,
      whitelistedCallers,
      commonConfig.feeCollector,
      whitelistedNfpms,
      whitelistedSwapRouters,
    );
  }

  return contracts;
}

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
    const deployedAddress =
      "0x" + txReceipt?.logs?.find((l) => l?.topics?.includes(createXTopic))?.topics?.[1]?.slice(26);
    contract = await ethers.getContractAt(contractName, deployedAddress);
    await printInfo(deployTx);
    log(2, `> address:\t${contract.target}`);
  }

  if (autoVerify) {
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
    let ret: Record<string, any> = {};
    for (let k in obj) {
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
