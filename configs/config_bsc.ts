import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  bsc_mainnet: {
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
    v3UtilsAddress: "",
    v4UtilsAddress: "",
  },
};

export const BscConfig: Record<string, IConfig> = {
  bsc_mainnet: {
    sleepTime: 10000,
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
    wrapToken: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
    typedTokens: [
      "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d", // USDC
      "0x55d398326f99059ff775485246999027b3197955", // USDT
      "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3", // DAI
      "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", // WBNB
      "0x90c97f71e18723b0cf0dfa30ee176ab653e89f40", // FRAX
      "0xc5f0f7b66764f6ec8c8dff7ba683102295e16409", // FDUSD
      "0x40af3827f39d0eacbf4a168f8d4ee67c121d11c9", // TUSD
      "0xe9e7cea3dedca5984780bafc599bd69add087d56", // BUSD
      "0x0782b6d8c4551b9760e74c0545a9bcd90bdc41e5", // lisUSD
      "0x2170ed0880ac9a755fd29b2688956bd959f933f8", // Binance-Peg WETH
      "0x4db5a66e937a9f4473fa95b1caf1d1e1d62e29ea", // WETH
      "0x26c5e01524d2e6280a48f2c50ff6de7e52e9611c", // wstETH
      "0x7130d2a12b9bcbfae4f2634d864a1ee1ce3ead9c", // BTCB
      "0xf6718b2701d4a6498ef77d7c152b2137ab28b8a3", // STBTC
      "0x7c1cca5b25fa0bc9af9275fb53cba89dc172b878", // Bridged Magpie-Peg BTC
      "0x4aae823a6a0b376de6a78e74ecc5b079d38cbcf7", // SOLVBTC
      "0x1346b618dc92810ec74163e4c27004c921d446a5", // XSOLVBTC
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WBNB
      1, // FRAX
      1, // FDUSD
      1, // TUSD
      1, // BUSD
      1, // lisUSD
      3, // Binance-Peg WETH
      3, // WETH
      3, // wstETH
      4, // BTCB
      4, // STBTC
      4, // Bridged Magpie-Peg BTC
      4, // SOLVBTC
      4, // XSOLVBTC
    ],
    swapRouters: ["0x051DC16b2ECB366984d1074dCC07c342a9463999"],
    nfpmAddresses: [
      "0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613",
      "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
      "0xF70c086618dcf2b1A461311275e00D6B722ef914",
    ],
    ...PrivateConfig.bsc_mainnet,
  },
};
