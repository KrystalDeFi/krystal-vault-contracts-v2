import { IConfig, IConfigPrivate, IConfigShared } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  robinhood_mainnet: {
    privateVault: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateVaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateConfigManager: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateVaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateV3UtilsStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateV4UtilsStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    v3UtilsAddress: "0xb4acbC082b5e7dEd571c98EE4257778a9D784B36",
    v4UtilsAddress: "0xCb3d2a42022741B06f9B38459e3DD1Ee9A64D129",
  },
};

// Robinhood has Uniswap V3 + V4, but no Pancake Infinity and no Aerodrome — those
// strategy blocks (and pancakeV4NfpmAddresses) stay off.
const SharedConfig: Record<string, IConfigShared> = {
  robinhood_mainnet: {
    sharedSwapDataSignatureLib: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedVaultPreviewLib: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedV4SwapPipeline: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedVault: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedVaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedConfigManager: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedVaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedVaultGateway: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedV3Strategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedV4StrategyLib: {
      enabled: true,
      autoVerifyContract: true,
    },
    sharedV4Strategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    v4NfpmAddresses: ["0x58daec3116aae6d93017baaea7749052e8a04fa7"],
  },
};

// Robinhood Chain (Arbitrum Orbit L2, chain id 4663) — private + shared vault deployment.
// Uniswap V3 and V4 are live; the public vault stack is not deployed here.
export const RobinhoodConfig: Record<string, IConfig> = {
  robinhood_mainnet: {
    sleepTime: 10000,
    vault: {
      enabled: false,
    },
    vaultAutomator: {
      enabled: false,
    },
    vaultFactory: {
      enabled: false,
    },
    wrapToken: "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73",
    swapRouters: ["0xeC04bAb6F0Fa7068a2eCD17EC70AA99b09e814b8"],
    nfpmAddresses: [
      "0x73991a25c818bf1f1128deaab1492d45638de0d3", // Uniswap V3
    ],
    ...PrivateConfig.robinhood_mainnet,
    ...SharedConfig.robinhood_mainnet,
  },
};
