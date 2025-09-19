import { IConfig } from "./interfaces";

export const BaseConfig: Record<string, IConfig> = {
  base_mainnet: {
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
    // Aerodrome contracts
    lpStrategyAerodrome: {
      enabled: true,
      autoVerifyContract: true,
    },
    lpValidatorAerodrome: {
      enabled: true,
      autoVerifyContract: true,
    },
    rewardSwapper: {
      enabled: true,
      autoVerifyContract: true,
    },
    farmingStrategyValidator: {
      enabled: true,
      autoVerifyContract: true,
    },
    farmingStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    // -------------------
    wrapToken: "0x4200000000000000000000000000000000000006",
    typedTokens: [
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", // USDC
      "0xfde4c96c8593536e31f229ea8f37b2ada2699bb2", // USDT
      "0x50c5725949a6f0c72e6c4a641f24049a917db0cb", // DAI
      "0x4200000000000000000000000000000000000006", // WETH
      "0xd9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca", // USDBC
      "0x820c137fa70c8691f0e44dc420a5e53c168921dc", // USDS
      "0xc1cba3fcea344f92d9239c08c0568f6f2f0ee452", // wstETH
      "0x2ae3f1ec7f1f5012cfeab0185bfc7aa3cf0dec22", // CBETH
      "0xb6fe221fe9eef5aba221c348ba20a1bf5e73624c", // RETH
      "0xb29749498954a3a821ec37bde86e386df3ce30b6", // LSETH
      "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf", // cbBTC
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WETH
      1, // USDBC
      1, // USDS
      2, // wstETH
      2, // CBETH
      2, // RETH
      2, // LSETH
      3, // cbBTC
    ],
    swapRouters: ["0x6fD481970744F9Bc0044a81859FD92431a2Dd67D"],
    nfpmAddresses: [
      "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
      "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
      "0x80C7DD17B01855a6D2347444a0FCC36136a314de",
    ],
    aerodromeNfpmAddresses: ["0x827922686190790b37229fd06084350E74485b72"],
    aerodromeGaugeFactories: [
      "0xD30677bd8dd15132F251Cb54CbDA552d2A05Fb08", // Aerodrome CLGaugeFactory on Base
    ],
  },
};
