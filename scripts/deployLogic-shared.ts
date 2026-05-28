import { BaseContract, encodeBytes32String, solidityPacked } from "ethers";
import { ethers, network, run } from "hardhat";
import { isArray, uniq } from "lodash";
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
import type { SharedVaultPreviewLib } from "../typechain-types/contracts/shared-vault/libraries";
import type {
  SharedAerodromeStrategy,
  SharedStrategyBeacon,
  SharedStrategyProxy,
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
  sharedVaultPreviewLib?: SharedVaultPreviewLib;
  sharedVault?: SharedVault;
  sharedVaultFactory?: SharedVaultFactory;
  sharedConfigManager?: SharedConfigManager;
  sharedVaultAutomator?: SharedVaultAutomator;
  sharedVaultGateway?: SharedVaultGateway;
  // Strategy implementations (logic only — not whitelisted directly)
  sharedV3Strategy?: SharedV3Strategy;
  sharedV4StrategyLib?: BaseContract;
  sharedV4Strategy?: SharedV4Strategy;
  sharedPancakeV4StrategyLib?: BaseContract;
  sharedPancakeV4Strategy?: BaseContract;
  sharedAerodromeStrategy?: SharedAerodromeStrategy;
  // Beacons — one per strategy type; call setImplementation() to upgrade
  sharedV3StrategyBeacon?: SharedStrategyBeacon;
  sharedV4StrategyBeacon?: SharedStrategyBeacon;
  sharedPancakeV4StrategyBeacon?: SharedStrategyBeacon;
  sharedAerodromeBeacon?: SharedStrategyBeacon;
  // Proxies — whitelisted in ConfigManager; address never changes on upgrade
  sharedV3StrategyProxy?: SharedStrategyProxy;
  sharedV4StrategyProxy?: SharedStrategyProxy;
  sharedPancakeV4StrategyProxy?: SharedStrategyProxy;
  sharedAerodromeProxy?: SharedStrategyProxy;
}

const SHARED_VAULT_PREVIEW_LIB =
  "contracts/shared-vault/libraries/SharedVaultPreviewLib.sol:SharedVaultPreviewLib";
const SHARED_V4_STRATEGY_LIB =
  "contracts/shared-vault/libraries/SharedV4StrategyLib.sol:SharedV4StrategyLib";
const SHARED_PANCAKE_V4_STRATEGY_LIB =
  "contracts/shared-vault/libraries/SharedPancakeV4StrategyLib.sol:SharedPancakeV4StrategyLib";

export function getSharedVaultLibrariesForDeployment(
  existingContract: Record<string, any> | undefined,
  contracts: SharedContracts,
): Record<string, string> | undefined {
  const previewLibAddress =
    (contracts.sharedVaultPreviewLib?.target as string | undefined) ?? existingContract?.["sharedVaultPreviewLib"];

  return previewLibAddress ? { [SHARED_VAULT_PREVIEW_LIB]: previewLibAddress } : undefined;
}

export function getSharedV4StrategyLibrariesForDeployment(
  existingContract: Record<string, any> | undefined,
  contracts: SharedContracts,
): Record<string, string> | undefined {
  const strategyLibAddress =
    (contracts.sharedV4StrategyLib?.target as string | undefined) ?? existingContract?.["sharedV4StrategyLib"];

  return strategyLibAddress ? { [SHARED_V4_STRATEGY_LIB]: strategyLibAddress } : undefined;
}

export function getSharedPancakeV4StrategyLibrariesForDeployment(
  existingContract: Record<string, any> | undefined,
  contracts: SharedContracts,
): Record<string, string> | undefined {
  const strategyLibAddress =
    (contracts.sharedPancakeV4StrategyLib?.target as string | undefined)
    ?? existingContract?.["sharedPancakeV4StrategyLib"];

  return strategyLibAddress ? { [SHARED_PANCAKE_V4_STRATEGY_LIB]: strategyLibAddress } : undefined;
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

  // 2. Deploy SharedVaultPreviewLib (required by SharedVault)
  if (networkConfig.sharedVaultPreviewLib?.enabled) {
    contracts.sharedVaultPreviewLib = (await deployContract(
      ++step,
      networkConfig.sharedVaultPreviewLib?.autoVerifyContract,
      "SharedVaultPreviewLib",
      existingContract?.["sharedVaultPreviewLib"],
      "contracts/shared-vault/libraries/SharedVaultPreviewLib.sol:SharedVaultPreviewLib",
    )) as SharedVaultPreviewLib;
  }

  // 3. Deploy SharedVault implementation
  if (networkConfig.sharedVault?.enabled) {
    const sharedVaultLibraries = getSharedVaultLibrariesForDeployment(existingContract, contracts);
    if (!existingContract?.["sharedVault"] && !sharedVaultLibraries) {
      throw new Error(
        "SharedVault deployment requires SharedVaultPreviewLib. Enable sharedVaultPreviewLib deployment or provide existingContract.sharedVaultPreviewLib.",
      );
    }

    contracts.sharedVault = (await deployContract(
      ++step,
      networkConfig.sharedVault?.autoVerifyContract,
      "SharedVault",
      existingContract?.["sharedVault"],
      "contracts/shared-vault/core/SharedVault.sol:SharedVault",
      undefined,
      undefined,
      undefined,
      sharedVaultLibraries,
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

  // 4. Deploy SharedV3Strategy + beacon + proxy
  if (networkConfig.sharedV3Strategy?.enabled) {
    contracts.sharedV3Strategy = (await deployContract(
      ++step,
      networkConfig.sharedV3Strategy?.autoVerifyContract,
      "SharedV3Strategy",
      existingContract?.["sharedV3Strategy"],
      "contracts/shared-vault/strategies/SharedV3Strategy.sol:SharedV3Strategy",
      undefined,
      ["address", "address"],
      [getSharedStrategySwapRouter(), lpFeeTakerAddress],
    )) as SharedV3Strategy;

    const implAddr = existingContract?.["sharedV3Strategy"] || contracts.sharedV3Strategy?.target;
    contracts.sharedV3StrategyBeacon = (await deployContract(
      `${step}.beacon`,
      networkConfig.sharedV3Strategy?.autoVerifyContract,
      "SharedStrategyBeacon",
      existingContract?.["sharedV3StrategyBeacon"],
      "contracts/shared-vault/strategies/SharedStrategyBeacon.sol:SharedStrategyBeacon",
      `${SALT ?? ""}-v3-b`,
      ["address", "address"],
      [implAddr, contractAdmin],
    )) as SharedStrategyBeacon;

    const beaconAddr = existingContract?.["sharedV3StrategyBeacon"] || contracts.sharedV3StrategyBeacon?.target;
    contracts.sharedV3StrategyProxy = (await deployContract(
      `${step}.proxy`,
      networkConfig.sharedV3Strategy?.autoVerifyContract,
      "SharedStrategyProxy",
      existingContract?.["sharedV3StrategyProxy"],
      "contracts/shared-vault/strategies/SharedStrategyProxy.sol:SharedStrategyProxy",
      `${SALT ?? ""}-v3-p`,
      ["address"],
      [beaconAddr],
    )) as SharedStrategyProxy;
  }

  // 5. Deploy SharedV4StrategyLib + SharedV4Strategy + beacon + proxy
  if (networkConfig.sharedV4Strategy?.enabled) {
    contracts.sharedV4StrategyLib = (await deployContract(
      ++step,
      networkConfig.sharedV4StrategyLib?.autoVerifyContract ?? networkConfig.sharedV4Strategy?.autoVerifyContract,
      "SharedV4StrategyLib",
      existingContract?.["sharedV4StrategyLib"],
      SHARED_V4_STRATEGY_LIB,
    )) as BaseContract;

    const sharedV4StrategyLibraries = getSharedV4StrategyLibrariesForDeployment(existingContract, contracts);
    contracts.sharedV4Strategy = (await deployContract(
      ++step,
      networkConfig.sharedV4Strategy?.autoVerifyContract,
      "SharedV4Strategy",
      existingContract?.["sharedV4Strategy"],
      "contracts/shared-vault/strategies/SharedV4Strategy.sol:SharedV4Strategy",
      undefined,
      ["address"],
      [getSharedStrategySwapRouter()],
      sharedV4StrategyLibraries,
    )) as SharedV4Strategy;

    const implAddr = existingContract?.["sharedV4Strategy"] || contracts.sharedV4Strategy?.target;
    contracts.sharedV4StrategyBeacon = (await deployContract(
      `${step}.beacon`,
      networkConfig.sharedV4Strategy?.autoVerifyContract,
      "SharedStrategyBeacon",
      existingContract?.["sharedV4StrategyBeacon"],
      "contracts/shared-vault/strategies/SharedStrategyBeacon.sol:SharedStrategyBeacon",
      `${SALT ?? ""}-v4-b`,
      ["address", "address"],
      [implAddr, contractAdmin],
    )) as SharedStrategyBeacon;

    const beaconAddr = existingContract?.["sharedV4StrategyBeacon"] || contracts.sharedV4StrategyBeacon?.target;
    contracts.sharedV4StrategyProxy = (await deployContract(
      `${step}.proxy`,
      networkConfig.sharedV4Strategy?.autoVerifyContract,
      "SharedStrategyProxy",
      existingContract?.["sharedV4StrategyProxy"],
      "contracts/shared-vault/strategies/SharedStrategyProxy.sol:SharedStrategyProxy",
      `${SALT ?? ""}-v4-p`,
      ["address"],
      [beaconAddr],
    )) as SharedStrategyProxy;
  }

  // 6. Deploy SharedPancakeV4StrategyLib + SharedPancakeV4Strategy + beacon + proxy
  if (networkConfig.sharedPancakeV4Strategy?.enabled) {
    contracts.sharedPancakeV4StrategyLib = (await deployContract(
      ++step,
      networkConfig.sharedPancakeV4StrategyLib?.autoVerifyContract
        ?? networkConfig.sharedPancakeV4Strategy?.autoVerifyContract,
      "SharedPancakeV4StrategyLib",
      existingContract?.["sharedPancakeV4StrategyLib"],
      SHARED_PANCAKE_V4_STRATEGY_LIB,
    )) as BaseContract;

    const sharedPancakeV4StrategyLibraries = getSharedPancakeV4StrategyLibrariesForDeployment(
      existingContract,
      contracts,
    );
    contracts.sharedPancakeV4Strategy = await deployContract(
      ++step,
      networkConfig.sharedPancakeV4Strategy?.autoVerifyContract,
      "SharedPancakeV4Strategy",
      existingContract?.["sharedPancakeV4Strategy"],
      "contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol:SharedPancakeV4Strategy",
      undefined,
      ["address"],
      [getSharedStrategySwapRouter()],
      sharedPancakeV4StrategyLibraries,
    );

    const implAddr = existingContract?.["sharedPancakeV4Strategy"] || contracts.sharedPancakeV4Strategy?.target;
    contracts.sharedPancakeV4StrategyBeacon = (await deployContract(
      `${step}.beacon`,
      networkConfig.sharedPancakeV4Strategy?.autoVerifyContract,
      "SharedStrategyBeacon",
      existingContract?.["sharedPancakeV4StrategyBeacon"],
      "contracts/shared-vault/strategies/SharedStrategyBeacon.sol:SharedStrategyBeacon",
      `${SALT ?? ""}-pcsv4-b`,
      ["address", "address"],
      [implAddr, contractAdmin],
    )) as SharedStrategyBeacon;

    const beaconAddr =
      existingContract?.["sharedPancakeV4StrategyBeacon"] || contracts.sharedPancakeV4StrategyBeacon?.target;
    contracts.sharedPancakeV4StrategyProxy = (await deployContract(
      `${step}.proxy`,
      networkConfig.sharedPancakeV4Strategy?.autoVerifyContract,
      "SharedStrategyProxy",
      existingContract?.["sharedPancakeV4StrategyProxy"],
      "contracts/shared-vault/strategies/SharedStrategyProxy.sol:SharedStrategyProxy",
      `${SALT ?? ""}-pcsv4-p`,
      ["address"],
      [beaconAddr],
    )) as SharedStrategyProxy;
  }

  // 7. Deploy SharedAerodromeStrategy + beacon + proxy (single; nfpm passed per-call, validated by ConfigManager)
  if (networkConfig.sharedAerodromeStrategy?.enabled) {
    contracts.sharedAerodromeStrategy = (await deployContract(
      ++step,
      networkConfig.sharedAerodromeStrategy?.autoVerifyContract,
      "SharedAerodromeStrategy",
      existingContract?.["sharedAerodromeStrategy"],
      "contracts/shared-vault/strategies/SharedAerodromeStrategy.sol:SharedAerodromeStrategy",
      undefined,
      ["address", "address"],
      [getSharedStrategySwapRouter(), lpFeeTakerAddress],
    )) as SharedAerodromeStrategy;

    const implAddr = existingContract?.["sharedAerodromeStrategy"] || contracts.sharedAerodromeStrategy?.target;
    contracts.sharedAerodromeBeacon = (await deployContract(
      `${step}.beacon`,
      networkConfig.sharedAerodromeStrategy?.autoVerifyContract,
      "SharedStrategyBeacon",
      existingContract?.["sharedAerodromeBeacon"],
      "contracts/shared-vault/strategies/SharedStrategyBeacon.sol:SharedStrategyBeacon",
      `${SALT ?? ""}-aero-b`,
      ["address", "address"],
      [implAddr, contractAdmin],
    )) as SharedStrategyBeacon;

    const beaconAddr = existingContract?.["sharedAerodromeBeacon"] || contracts.sharedAerodromeBeacon?.target;
    contracts.sharedAerodromeProxy = (await deployContract(
      `${step}.proxy`,
      networkConfig.sharedAerodromeStrategy?.autoVerifyContract,
      "SharedStrategyProxy",
      existingContract?.["sharedAerodromeProxy"],
      "contracts/shared-vault/strategies/SharedStrategyProxy.sol:SharedStrategyProxy",
      `${SALT ?? ""}-aero-p`,
      ["address"],
      [beaconAddr],
    )) as SharedStrategyProxy;
  }

  // 7. Deploy SharedVaultAutomator
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
      await sleep(10000);
      await contracts.sharedVaultGateway.initialize(contractAdmin, gatewaySwapRouter, networkConfig.wrapToken);
    }
  }

  // Initialize SharedVaultFactory
  if (networkConfig.sharedVaultFactory?.enabled && !existingContract?.["sharedVaultFactory"]) {
    await sleep(10000);
    await contracts.sharedVaultFactory?.initialize(
      contractAdmin,
      existingContract?.["sharedConfigManager"] || contracts.sharedConfigManager?.target,
      existingContract?.["sharedVault"] || contracts.sharedVault?.target,
      networkConfig.wrapToken!,
    );
  }

  // Initialize SharedConfigManager
  if (networkConfig.sharedConfigManager?.enabled && !existingContract?.["sharedConfigManager"]) {
    // Whitelist proxy addresses — never the raw implementations.
    // On upgrade: beacon.setImplementation(newImpl) — no re-whitelisting needed.
    const whitelistedTargets = [
      existingContract?.["sharedV3StrategyProxy"] || contracts.sharedV3StrategyProxy?.target,
      existingContract?.["sharedV4StrategyProxy"] || contracts.sharedV4StrategyProxy?.target,
      existingContract?.["sharedPancakeV4StrategyProxy"] || contracts.sharedPancakeV4StrategyProxy?.target,
      existingContract?.["sharedAerodromeProxy"] || contracts.sharedAerodromeProxy?.target,
    ].filter(Boolean) as string[];

    const whitelistedCallers = [
      existingContract?.["sharedVaultAutomator"] || contracts.sharedVaultAutomator?.target,
    ].filter(Boolean) as string[];

    const whitelistedNfpms = uniq([
      ...(networkConfig.nfpmAddresses ?? []),
      ...(networkConfig.aerodromeNfpmAddresses ?? []),
      ...(networkConfig.v4NfpmAddresses ?? []),
      ...(networkConfig.pancakeV4NfpmAddresses ?? []),
    ]).filter(Boolean) as string[];
    const whitelistedSwapRouters = (networkConfig.swapRouters ?? []) as string[];

    await sleep(10000);

    await contracts.sharedConfigManager?.initialize(
      contractAdmin,
      whitelistedTargets,
      whitelistedCallers,
      commonConfig.feeCollector,
      commonConfig.platformFeeBasisPoint,
      whitelistedNfpms,
      whitelistedSwapRouters,
    );
  }

  return contracts;
}

function getSharedStrategySwapRouter(): string {
  const swapRouter = networkConfig.sharedVaultGateway?.swapRouter ?? networkConfig.swapRouters?.[0];
  if (!swapRouter) {
    throw new Error("shared strategies require sharedVaultGateway.swapRouter or at least one swapRouters entry");
  }
  return swapRouter.toString();
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
  libraries?: Record<string, string>,
): Promise<BaseContract> {
  log(1, `${step}. Deploying '${contractName}'`);
  log(1, "------------------------------------");
  const factory = await ethers.getContractAt("ICreateX", createXContractAddress, await ethers.provider.getSigner());
  let contract;

  if (contractAddress) {
    log(2, `> contract already exists`);
    log(2, `> address:\t${contractAddress}`);
    contract = await ethers.getContractAt(contractName, contractAddress, await ethers.provider.getSigner());
  } else {
    let bytecode = (await ethers.getContractFactory(contractName, libraries ? { libraries } : undefined)).bytecode;
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
          ...(libraries ? { libraries } : {}),
        });
      } else {
        if (!!contractLocation) {
          await run("verify:verify", {
            address: contract.target,
            constructorArguments: args,
            contract: contractLocation,
            ...(libraries ? { libraries } : {}),
          });
        } else {
          await run("verify:verify", {
            address: contract.target,
            constructorArguments: args,
            ...(libraries ? { libraries } : {}),
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
