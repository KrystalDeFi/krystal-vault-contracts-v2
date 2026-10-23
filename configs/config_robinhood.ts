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
    privateAerodromeFarmingStrategy: {
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
    aerodromeGaugeFactories: [
      "0x6Bdf3B9A782c28D6259356d0Cb7Ae22Ab1368863", // Up (Aerodrome fork)
      "0xf437f62053ACB121665b8fDBfeA8F214FB8E589d", // Aero
    ],
    aeroEmissionToken: "0x9e148C5716b5aAdCFD3B71cEAE9EE7a9e22C29E2", // xAERO
  },
};

// Robinhood has Uniswap V3 + V4, Up (an Aerodrome Slipstream fork) and Aero (the merged
// Aerodrome + Velodrome), both served by the Aerodrome strategy, but no Pancake Infinity —
// that strategy block (and pancakeV4NfpmAddresses) stays off.
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
    sharedAerodromeStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    v4NfpmAddresses: ["0x58daec3116aae6d93017baaea7749052e8a04fa7"],
  },
};

// Robinhood Chain (Arbitrum Orbit L2, chain id 4663) — private + shared vault deployment.
// Uniswap V3, V4, Up (Aerodrome fork) and Aero are live; the public vault stack is not deployed here.
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
    aerodromeNfpmAddresses: [
      "0x07F44c47743A2f36414A82b9F558ECFCf0EEdCEf", // Up (Aerodrome fork)
      "0x4857DB576eE0e45F10525eC59527BfD10beeC60b", // Aero Slipstream (same address on every chain)
    ],
    ...PrivateConfig.robinhood_mainnet,
    ...SharedConfig.robinhood_mainnet,
  },
};
