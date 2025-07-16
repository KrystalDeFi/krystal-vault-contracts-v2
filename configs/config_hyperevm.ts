import { IConfig } from "./interfaces";

export const BaseConfig: Record<string, IConfig> = {
  base_mainnet: {
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
      3, // UETH
      4, // UBTC
      1, // USDe
      1, // feUSD
      1, // hbUSDT
    ],
    swapRouters: [],
    nfpmAddresses: ["0x6eDA206207c09e5428F281761DdC0D300851fBC8"],
  },
};
