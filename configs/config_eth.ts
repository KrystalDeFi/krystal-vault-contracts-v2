import { IConfig, IConfigPrivate } from "./interfaces";

const PrivateConfig: Record<string, IConfigPrivate> = {
  eth_mainnet: {
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
    privatePancakeV3FarmingStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateMerklStrategy: {
      enabled: true,
      autoVerifyContract: true,
    },
    privateKyberFairFlowStrategy: {
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
    v3UtilsAddress: "0xb4acbc082b5e7ded571c98ee4257778a9d784b36",
    v4UtilsAddress: "0xCb3d2a42022741B06f9B38459e3DD1Ee9A64D129",
    pancakeV3MasterChef: "0x556B9306565093C855AEA9AE92A594704c2Cd59e",
    merklDistributor: "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae",
    uniswapV4KEMHook: "0x4440854B2d02C57A0Dc5c58b7A884562D875c0c4",
  },
};

export const EthereumConfig: Record<string, IConfig> = {
  eth_mainnet: {
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
    wrapToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    typedTokens: [
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
      "0xdAC17F958D2ee523a2206206994597C13D831ec7", // USDT
      "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
      "0x4c9edd5852cd905f086c759e8383e09bff1e68b3", // USDe
      "0x40d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2f", // GHO
      "0x853d955acef822db058eb8505911ed77f175b99e", // FRAX
      "0x5f98805a4e8be255a32880fdec7f6728c6568ba0", // LUSD
      "0x8292bb45bf1ee4d140127049757c2e0ff06317ed", // RLUSD
      "0x8d0d000ee44948fc98c9b98a4fa4921476f08b0d", // USD1
      "0x73a15fed60bf67631dc6cd7bc5b6e8da8190acf5", // USD0
      "0x6c3ea9036406852006290770bedfcaba0e23a0e8", // PYUSD
      "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0", // wstETH
      "0xbf5495efe5db9ce00f80364c8b423567e58d2110", // ezETH
      "0xae78736cd615f374d3085123a210448e74fc6393", // rETH
      "0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee", // weETH
      "0xd5f7838f5c461feff7fe49ea5ebaf7728bb0adfa", // METH
      "0xf951e335afb289353dc249e82926178eac7ded78", // SWETH
      "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", // WBTC
      "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf", // CBBTC
      "0x18084fba666a33d37592fa2633fd49a74dd93a88", // tBTC
      "0x8236a87084f8b84306f72007f36f2618a5634494", // LBTC
    ],
    // 1 for stable, 2 for ETH,...
    typedTokensTypes: [
      1, // USDC
      1, // USDT
      1, // DAI
      2, // WETH
      1, // USDe
      1, // GHO
      1, // FRAX
      1, // LUSD
      1, // RLUSD
      1, // USD1
      1, // USD0
      1, // PYUSD
      2, // wstETH
      2, // ezETH
      2, // rETH
      2, // weETH
      2, // METH
      2, // SWETH
      3, // WBTC
      3, // CBBTC
      3, // tBTC
      3, // LBTC
    ],
    swapRouters: ["0x70270C228c5B4279d1578799926873aa72446CcD"],
    nfpmAddresses: [
      "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
      "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
      "0x2214A42d8e2A1d20635c2cb0664422c528B6A432",
    ],
    ...PrivateConfig.eth_mainnet,
  },
};
