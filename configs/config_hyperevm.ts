import { commonConfig } from "./config_common";
import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  hyperevm_mainnet: {
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
    v3UtilsAddress: "0x3A7e46212Ac7d61E44bb9bA926E3737Af5A65EC6",
    v4UtilsAddress: "0xE91D4cC5d8b97379d740A1f19c728EAb76A16228",
  },
};

export const HyperevmConfig: Record<string, IConfig> = {
  hyperevm_mainnet: {
    sleepTime: 20000,
    vault: {
      enabled: true,
      autoVerifyContract: true,
    },
    vaultAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    vaultFactory: {
      enabled: true,
      autoVerifyContract: true,
    },
    configManager: {
      enabled: true,
      autoVerifyContract: true,
    },
    poolOptimalSwapper: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpValidator: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpFeeTaker: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpChainingStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    merklStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    merklAutomator: {
      enabled: true,
      autoVerifyContract: true,
    },
    wrapToken: "0x5555555555555555555555555555555555555555",
    typedTokens: [
      "0xb8ce59fc3717ada4c02eadf9682a9e934f625ebb", // USD₮0
      "0x9ab96a4668456896d45c301bc3a15cee76aa7b8d", // rUSDC
      "0xb50a96253abdf803d85efcdce07ad8becbc52bd5", // USDHL
      "0x5555555555555555555555555555555555555555", // WHYPE
      "0x5748ae796ae46a4f1348a1693de4b50560485562", // LHYPE
      "0xfd739d4e423301ce9385c1fb8850539d657c296d", // kHYPE
      "0x96c6cbb6251ee1c257b2162ca0f39aa5fa44b1fb", // hbHYPE
      "0x81e064d0eb539de7c3170edf38c1a42cbd752a76", // lstHYPE
      "0xdabb040c428436d41cecd0fb06bcfdbaad3a9aa8", // mHYPE
      "0x94e8396e0869c9f2200760af0621afd240e1cf38", // wstHYPE
      "0xbe6727b535545c67d5caa73dea54865b92cf7907", // UETH
      "0x9fdbda0a5e284c32744d2f17ee5c74b284993463", // UBTC
      "0x5d3a1ff2b6bab83b63cd9ad0787074081a52ef34", // USDe
      "0x02c6a2fa58cc01a18b8d9e00ea48d65e4df26c70", // feUSD
      "0x5e105266db42f78fa814322bce7f388b4c2e61eb", // hbUSDT
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USD₮0
      1, // rUSDC
      1, // USDHL
      2, // WHYPE
      2, // LHYPE
      2, // kHYPE
      2, // hbHYPE
      2, // lstHYPE
      2, // mHYPE
      2, // wstHYPE
      3, // UETH
      4, // UBTC
      1, // USDe
      1, // feUSD
      1, // hbUSDT
    ],
    encodedLpConfigs: [
      // WHYPE
      commonConfig.hypeConfig,
      // USD₮0
      commonConfig.stableConfigWith6Decimals,
      // USDHL
      commonConfig.stableConfigWith6Decimals,
      // LHYPE
      commonConfig.hypeConfig,
      // kHYPE
      commonConfig.hypeConfig,
      // wstHYPE
      commonConfig.hypeConfig,
      // UETH
      commonConfig.nativeConfig,
      // UBTC
      commonConfig.btcConfig,
      // USDe
      commonConfig.stableConfigWith18Decimals,
      // feUSD
      commonConfig.stableConfigWith18Decimals,
    ],
    swapRouters: ["0x14b37a44067c877F46aCE21d42ccEC4e9593A941"],
    nfpmAddresses: [
      "0x6eDA206207c09e5428F281761DdC0D300851fBC8",
      "0xeaD19AE861c29bBb2101E834922B2FEee69B9091",
      "0xC8352A2EbA29F4d9BD4221c07D3461BaCc779088",
    ],
    ...PrivateConfig.hyperevm_mainnet,
  },
};
