import { IConfig, IConfigPrivate } from "./interfaces";

// Arc (Circle's Layer-1, chain id 5042) — private vault deployment.
//
// Arc runs USDC as its native gas token and targets the Osaka hardfork, so the
// cancun-compiled bytecode in this repo is opcode-compatible (PUSH0 / MCOPY /
// TSTORE are all available). None of the private-vault contracts read
// `block.prevrandao` (always 0 on Arc) or `blockhash`, and the only
// `block.timestamp` use is an expiry comparison in PrivateVaultAutomator, which
// is unaffected by Arc's non-strictly-increasing timestamps.
//
// PRE-DEPLOY CHECKLIST — all three are external to this repo and will silently
// break the run if skipped:
//   1. CreateX must exist at 0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed.
//      deployLogic-private.ts calls it unconditionally; Arc's docs only list the
//      Arachnid CREATE2 factory at 0x4e59b44847b379578588920cA78FbF26c0B4956C.
//      Verify on-chain before deploying, exactly as we did for Robinhood.
//   2. V3Utils and V4UtilsRouter must already be deployed on Arc — they are
//      constructor args of the two strategies below.
//   3. Arc enforces a 20 gwei minimum base fee and DROPS cheaper transactions
//      with no error receipt. Ensure maxFeePerGas >= 20 gwei on the deploy tx.
//
// OPS NOTE — on Arc the native balance and the ERC-20 USDC balance
// (0x3600000000000000000000000000000000000000) are the same money behind two
// interfaces, at 18 and 6 decimals respectively. `sweepNativeToken` and
// `sweepToken([USDC])` therefore draw from one pot and must not be summed in
// off-chain accounting. EIP-7708 also emits native-movement Transfer logs at 18
// decimals from a system emitter, which will mis-scale indexers that assume the
// 6-decimal ERC-20 view.
const PrivateConfig: Record<string, IConfigPrivate> = {
  arc_mainnet: {
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
    // Canonical cross-chain CREATE2 addresses. EXPECTED BUT UNVERIFIED on Arc —
    // neither sibling repo's contracts.json has a 5042 entry yet. Confirm both
    // on-chain before deploying; a wrong address here bakes into the strategy
    // immutables and needs a redeploy to fix.
    v3UtilsAddress: "0xb4acbC082b5e7dEd571c98EE4257778a9D784B36",
    v4UtilsAddress: "0xCb3d2a42022741B06f9B38459e3DD1Ee9A64D129",
  },
};

// Uniswap V3 and V4 are both live on Arc. The shared vault stack is intentionally
// absent: Arc has no WETH/WUSDC-style wrapper, and deployLogic-shared.ts hard
// throws without `wrapToken` for both sharedVaultFactory and sharedVaultGateway.
// The private path never reads `wrapToken`, `nfpmAddresses` or `swapRouters`, so
// none of that blocks this deployment. The public vault stack is not deployed here.
export const ArcConfig: Record<string, IConfig> = {
  arc_mainnet: {
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
    // TODO: Krystal's aggregator router is not deployed on Arc yet. Left empty
    // rather than pointing at Uniswap's UniversalRouter
    // (0x4fca4a51ab4f23a7447b3284fbd7d73289a89fb1), which is a live router but
    // not what this field means on every other chain. Unused by the private path.
    swapRouters: [],
    nfpmAddresses: [
      "0x39654A85A4C05127f5Fd6ED22CAeC077A0fB1377", // Uniswap V3 NonfungiblePositionManager
    ],
    ...PrivateConfig.arc_mainnet,
  },
};
