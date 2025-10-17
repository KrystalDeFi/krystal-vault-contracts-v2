import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  arbitrum_mainnet: {
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
    pancakeV3MasterChef: "0x5e09ACf80C0296740eC5d6F643005a4ef8DaA694",
  },
};

export const ArbitrumConfig: Record<string, IConfig> = {
  arbitrum_mainnet: {
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
    wrapToken: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    typedTokens: [
      "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // USDC
      "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", // USDT
      "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1", // DAI
      "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", // WETH
      "0x7dff72693f6a4149b17e7c6314655f6a9f7c8b33", // GHO
      "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8", // USDC
      "0x6491c05A82219b8D1479057361ff1654749b876b", // USDS
      "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34", // USDe
      "0xd3443ee1e91af28e5fb858fbd0d72a63ba8046e0", // GUSDC
      "0x5979D7b546E38E414F7E9822514be443A4800529", // wstETH
      "0xec70dcb4a1efa46b8f2d97c310c9c4790ba5ffa8", // rETH
      "0x2416092f143378750bb29b79ed961ab195cceea5", // ezETH
      "0x4186bfc76e2e237523cbc30fd220fe055156b41f", // rsETH
      "0x1debd73e752beaf79865fd6446b0c970eae7732f", // cbETH
      "0x35751007a407ca6feffe80b3cb397736d2cf4dbe", // weETH
      "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f", // WBTC
      "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf", // CBBTC
      "0x3647c54c4c2c65bc7a2d63c0da2809b399dbbdc0", // SOLVBTC
      "0x6c84a8f1c29108f47a79964b5fe888d4f4d0de40", // TBTC
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WETH
      1, // GHO
      1, // USDC
      1, // USDS
      1, // USDe
      1, // GUSDC
      2, // wstETH
      2, // rETH
      2, // ezETH
      2, // rsETH
      2, // cbETH
      2, // weETH
      3, // WBTC
      3, // CBBTC
      3, // SOLVBTC
      3, // TBTC
    ],
    swapRouters: ["0x864F01c5E46b0712643B956BcA607bF883e0dbC5"],
    nfpmAddresses: [
      "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
      "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
      "0xF0cBce1942A68BEB3d1b73F0dd86C8DCc363eF49",
    ],
    ...PrivateConfig.arbitrum_mainnet,
  },
};
