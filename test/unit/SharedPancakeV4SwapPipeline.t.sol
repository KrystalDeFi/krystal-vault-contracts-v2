// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedPancakeV4Utils } from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";
import { SharedV4SwapPipeline } from "../../contracts/shared-vault/libraries/SharedV4SwapPipeline.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";

// ---------------------------------------------------------------------------
// Twin-parity coverage for SharedV4SwapPipeline.executePancake — the Pancake
// (infinity-core Currency) normalization entry into the shared `_run` pipeline.
// Mirrors SharedV4SwapPipeline.t.sol (the Uniswap V4 `execute` entry): the two
// entrypoints are protocol twins and must keep mirrored unit coverage, plus the
// Pancake-only positive native-currency normalization case.
// ---------------------------------------------------------------------------

contract SharedPancakeV4SwapPipelineTestToken is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract SharedPancakeV4SwapPipelineConfigManager {
  address public router;
  address public signer;
  uint64 public maxGasFeeX64 = type(uint64).max;
  address public feeRecipient;

  constructor(address _router, address _signer) {
    router = _router;
    signer = _signer;
  }

  function setFeeRecipient(address _feeRecipient) external {
    feeRecipient = _feeRecipient;
  }

  function isWhitelistedSwapRouter(address account) external view returns (bool) {
    return account == router;
  }

  function isWhitelistedSigner(address account) external view returns (bool) {
    return account == signer;
  }
}

contract SharedPancakeV4SwapPipelineRouter {
  function swapAll(address tokenIn, address tokenOut, uint256 amountOut) external {
    uint256 amountIn = ERC20(tokenIn).allowance(msg.sender, address(this));
    ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    ERC20(tokenOut).transfer(msg.sender, amountOut);
  }
}

contract SharedPancakeV4SwapPipelineHarness {
  address public immutable weth;
  ISharedConfigManager public immutable configManager;
  mapping(address => bool) public isVaultToken;

  constructor(address _configManager, address _weth) {
    configManager = ISharedConfigManager(_configManager);
    weth = _weth;
  }

  function setVaultToken(address token, bool allowed) external {
    isVaultToken[token] = allowed;
  }

  function executePancake(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    return SharedV4SwapPipeline.executePancake(swapRouter, token0, token1, amount0, amount1, swapParams);
  }

  function executePancakeWithInputs(
    address swapRouter,
    address token0,
    address token1,
    ISharedPancakeV4Utils.InputTokenParams[] memory inputTokens,
    uint64 gasFeeX64,
    ISharedPancakeV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    return SharedV4SwapPipeline.executePancakeWithInputs(swapRouter, token0, token1, inputTokens, gasFeeX64, swapParams);
  }
}

contract SharedPancakeV4SwapPipelineTest is Test {
  uint256 internal constant SIGNER_PK = 0xA11CE;

  SharedPancakeV4SwapPipelineTestToken internal token0;
  SharedPancakeV4SwapPipelineTestToken internal token1;
  SharedPancakeV4SwapPipelineRouter internal router;
  SharedPancakeV4SwapPipelineHarness internal harness;
  SharedPancakeV4SwapPipelineConfigManager internal configManager;
  address internal signer;
  uint256 internal nonce;

  function setUp() public {
    signer = vm.addr(SIGNER_PK);
    token0 = new SharedPancakeV4SwapPipelineTestToken("Token 0", "TK0");
    token1 = new SharedPancakeV4SwapPipelineTestToken("Token 1", "TK1");
    router = new SharedPancakeV4SwapPipelineRouter();
    configManager = new SharedPancakeV4SwapPipelineConfigManager(address(router), signer);
    harness = new SharedPancakeV4SwapPipelineHarness(address(configManager), address(token0));
    harness.setVaultToken(address(token0), true);
    harness.setVaultToken(address(token1), true);
  }

  // -------------------------------------------------------------------------
  // Signature-bound amountIn (twin of test_execute_swapsSignedParamAmountNotComputedBalance):
  // `swapParam.amountIn` must reach SharedSwapDataSignature.verify VERBATIM via the Pancake
  // normalization — never an on-chain computed balance.
  // -------------------------------------------------------------------------

  function test_executePancake_swapsSignedParamAmountNotComputedBalance() public {
    uint256 runtimeAmount = 10.5 ether; // realized withdraw proceeds
    uint256 signedAmountIn = 10 ether; // backend folded withdraw-liquidity slippage into this
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: signedAmountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), signedAmountIn, amountOut, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);

    assertEq(token0.balanceOf(address(router)), signedAmountIn, "router pulled exactly the signed amountIn");
    assertEq(total0, runtimeAmount - signedAmountIn, "slippage-buffer remainder stays in total0");
    assertEq(total1, amountOut, "swap output credited to total1");
    assertEq(token0.balanceOf(address(harness)), runtimeAmount - signedAmountIn, "harness keeps the remainder");
    assertEq(token1.balanceOf(address(harness)), amountOut, "harness received the swap output");
  }

  function test_executePancake_rejectsSignatureBoundToComputedBalance() public {
    uint256 runtimeAmount = 10.5 ether;
    uint256 signedAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: signedAmountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      // Signature over the runtime balance (the removed resolved-amount behavior) must not verify.
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmount, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  function test_executePancake_revertsWhenSignedAmountExceedsRuntimeBalance() public {
    uint256 runtimeAmount = 9 ether; // realized < signed
    uint256 signedAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: signedAmountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), signedAmountIn, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  function test_executePancake_zeroAmountInSkipsSwapInsteadOfResolvingToBalance() public {
    uint256 runtimeAmount = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 0,
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmount, 0, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);

    assertEq(total0, runtimeAmount, "total0 untouched by the skipped hop");
    assertEq(total1, 0, "no output credited");
    assertEq(token0.balanceOf(address(router)), 0, "router never called");
    assertEq(token0.balanceOf(address(harness)), runtimeAmount, "harness keeps its token0");
  }

  function test_executePancake_zeroAmountInWithAmountOutMinReverts() public {
    uint256 runtimeAmount = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmount, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  /// @dev Twin of SharedV4SwapPipeline's test: an empty-swapData hop with POSITIVE amountIn reaches
  ///      _swap's no-op guard (zero-amountIn hops short-circuit earlier). With amountOutMin == 0 it must
  ///      be a tolerated no-op — no signature check, no router call, amount stays in the totals.
  function test_executePancake_emptySwapDataWithPositiveAmountInIsNoOp() public {
    uint256 runtimeAmount = 10 ether;
    token0.mint(address(harness), runtimeAmount);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 3 ether, // covered by total0, but the hop carries no calldata
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 0,
      swapData: ""
    });

    (uint256 total0, uint256 total1) =
      harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);

    assertEq(total0, runtimeAmount, "dataless hop leaves total0 untouched");
    assertEq(total1, 0, "no output credited");
    assertEq(token0.balanceOf(address(harness)), runtimeAmount, "no tokens moved");
  }

  /// @dev Twin of SharedV4SwapPipeline's test: the revert half — empty swapData with a non-zero
  ///      amountOutMin is a stale slippage floor and must revert instead of being skipped.
  function test_executePancake_emptySwapDataWithPositiveAmountInAndMinOutReverts() public {
    uint256 runtimeAmount = 10 ether;
    token0.mint(address(harness), runtimeAmount);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 3 ether,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1,
      swapData: ""
    });

    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    harness.executePancake(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  // -------------------------------------------------------------------------
  // Reachability guards and the intermediate virtual ledger via the Pancake
  // normalization (twins of the V4 entry tests).
  // -------------------------------------------------------------------------

  function test_executePancake_rejectsUnreachableInputToken() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Intermediate", "TKX");

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 0,
      swapData: hex"01" // never reached — reachability check precedes signature verification
    });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    harness.executePancake(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  function test_executePancake_rejectsUnreachableOutputToken() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Stranded", "TKX");

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(tokenX)),
      amountOutMin: 0,
      swapData: hex"01"
    });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    harness.executePancake(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev Currency.wrap(address(0)) normalizes to the harness WETH; with no wrapped-native configured
  ///      the zero output must be rejected rather than tracked as an intermediate.
  function test_executePancake_rejectsZeroAddressNormalizedOutput() public {
    SharedPancakeV4SwapPipelineConfigManager configManager =
      new SharedPancakeV4SwapPipelineConfigManager(address(router), signer);
    SharedPancakeV4SwapPipelineHarness zeroWethHarness =
      new SharedPancakeV4SwapPipelineHarness(address(configManager), address(0));

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(0)),
      amountOutMin: 0,
      swapData: hex"01"
    });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    zeroWethHarness.executePancake(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev Pancake-side positive normalization: a native-currency hop (Currency.wrap(address(0)))
  ///      resolves to the harness WETH — here token0 — so the swap draws from the token0 totals and
  ///      verifies against a digest signed over the WETH address. Pins _normalizePancake's
  ///      `_vaultToken(native) -> weth` mapping with a real swap, not just the zero-weth rejection.
  function test_executePancake_nativeCurrencyInputNormalizesToWeth() public {
    uint256 amountIn = 4 ether;
    uint256 amountOut = 3 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), amountIn);
    token1.mint(address(router), amountOut);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(0)), // native — must normalize to weth == token0
      amountIn: amountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      // Digest is signed over the NORMALIZED token (weth/token0), proving normalization runs first.
      swapData: _signedSwapData(address(token0), address(token1), amountIn, amountOut, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.executePancake(address(router), address(token0), address(token1), amountIn, 0, swaps);

    assertEq(total0, 0, "native hop drew from the token0 (weth) totals");
    assertEq(total1, amountOut, "output credited to total1");
    assertEq(token0.balanceOf(address(router)), amountIn, "router pulled the normalized weth amount");
  }

  function test_executePancake_revertsWhenIntermediatePartiallyConsumed() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Intermediate", "TKX");
    uint256 intermediateOut = 5 ether;
    uint256 partialIn = 2 ether;
    uint256 finalOut = 1 ether;

    token0.mint(address(harness), 10 ether);
    tokenX.mint(address(router), intermediateOut);
    token1.mint(address(router), finalOut);

    bytes memory hop1Data =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(tokenX), intermediateOut));
    bytes memory hop2Data =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token1), finalOut));

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](2);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 10 ether,
      tokenOut: Currency.wrap(address(tokenX)),
      amountOutMin: intermediateOut,
      swapData: _signedSwapData(address(token0), address(tokenX), 10 ether, intermediateOut, hop1Data)
    });
    swaps[1] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: partialIn, // leaves 3 ether of tokenX in the ledger
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: finalOut,
      swapData: _signedSwapData(address(tokenX), address(token1), partialIn, finalOut, hop2Data)
    });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.executePancake(address(router), address(token0), address(token1), 10 ether, 0, swaps);
  }

  function test_executePancake_multiHopThroughIntermediate_succeeds() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Intermediate", "TKX");
    uint256 intermediateOut = 5 ether;
    uint256 finalOut = 4 ether;

    token0.mint(address(harness), 10 ether);
    tokenX.mint(address(router), intermediateOut);
    token1.mint(address(router), finalOut);

    bytes memory hop1Data =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(token0), address(tokenX), intermediateOut));
    bytes memory hop2Data =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token1), finalOut));

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](2);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 10 ether,
      tokenOut: Currency.wrap(address(tokenX)),
      amountOutMin: intermediateOut,
      swapData: _signedSwapData(address(token0), address(tokenX), 10 ether, intermediateOut, hop1Data)
    });
    swaps[1] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: intermediateOut, // explicit signed amount: hop 1's full output (the digest binds it)
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: finalOut,
      swapData: _signedSwapData(address(tokenX), address(token1), intermediateOut, finalOut, hop2Data)
    });

    (uint256 total0, uint256 total1) =
      harness.executePancake(address(router), address(token0), address(token1), 10 ether, 0, swaps);

    assertEq(total0, 0, "token0 fully consumed by hop 1");
    assertEq(total1, finalOut, "hop 2 output credited to total1");
    assertEq(tokenX.balanceOf(address(harness)), 0, "no stranded intermediate balance");
    assertEq(token1.balanceOf(address(harness)), finalOut, "harness holds the final output");
  }

  function test_executePancake_rejectsIdenticalTokenHop() public {
    token0.mint(address(harness), 1 ether);

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 0,
      swapData: hex"01" // never verified — the identical-token guard precedes signature checking
    });

    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    harness.executePancake(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev Twin of test_execute_skipsRouterWhitelistWhenNoSwaps for the Pancake entry.
  function test_executePancake_skipsRouterWhitelistWhenNoSwaps() public {
    address unWhitelistedRouter = address(0xBAD);
    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](0);

    (uint256 total0, uint256 total1) =
      harness.executePancake(unWhitelistedRouter, address(token0), address(token1), 3 ether, 7 ether, swaps);

    assertEq(total0, 3 ether, "amount0 passes through untouched");
    assertEq(total1, 7 ether, "amount1 passes through untouched");
  }

  // -------------------------------------------------------------------------
  // executePancakeWithInputs: twin-parity coverage of executeWithInputs (input
  // folding, the input gas-fee skim, and the seeded ledger for non-pool
  // vault-token inputs). Mirrors the executeWithInputs block in
  // SharedV4SwapPipeline.t.sol.
  // -------------------------------------------------------------------------

  /// @dev Twin of test_executeWithInputs_poolTokenInputsFoldIntoTotals.
  function test_executePancakeWithInputs_poolTokenInputsFoldIntoTotals() public {
    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](3);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 3 ether });
    inputs[1] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 7 ether });
    inputs[2] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(0xDEAD)), amount: 0 });

    (uint256 total0, uint256 total1) = harness.executePancakeWithInputs(
      address(router), address(token0), address(token1), inputs, 0, new ISharedPancakeV4Utils.SwapParams[](0)
    );

    assertEq(total0, 3 ether, "token0 input folded into total0");
    assertEq(total1, 7 ether, "token1 input folded into total1");
  }

  /// @dev Twin of test_executeWithInputs_nonPoolVaultTokenInput_swapsIntoPoolTokens.
  function test_executePancakeWithInputs_nonPoolVaultTokenInput_swapsIntoPoolTokens() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Source", "SRC");
    harness.setVaultToken(address(tokenX), true);
    tokenX.mint(address(harness), 10 ether);
    token0.mint(address(router), 6 ether);
    token1.mint(address(router), 4 ether);

    bytes memory hop0Data =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token0), uint256(6 ether)));
    bytes memory hop1Data =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token1), uint256(4 ether)));

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](1);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 10 ether });

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](2);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 6 ether,
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 6 ether,
      swapData: _signedSwapData(address(tokenX), address(token0), 6 ether, 6 ether, hop0Data)
    });
    swaps[1] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 4 ether,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 4 ether,
      swapData: _signedSwapData(address(tokenX), address(token1), 4 ether, 4 ether, hop1Data)
    });

    (uint256 total0, uint256 total1) =
      harness.executePancakeWithInputs(address(router), address(token0), address(token1), inputs, 0, swaps);

    assertEq(total0, 6 ether, "tokenX->token0 output credited to total0");
    assertEq(total1, 4 ether, "tokenX->token1 output credited to total1");
    assertEq(tokenX.balanceOf(address(harness)), 0, "seeded input fully consumed");
    assertEq(token0.balanceOf(address(harness)), 6 ether, "harness holds the token0 output");
    assertEq(token1.balanceOf(address(harness)), 4 ether, "harness holds the token1 output");
  }

  /// @dev Twin of test_executeWithInputs_mergesDuplicateInputEntries.
  function test_executePancakeWithInputs_mergesDuplicateInputEntries() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Source", "SRC");
    harness.setVaultToken(address(tokenX), true);
    tokenX.mint(address(harness), 10 ether);
    token0.mint(address(router), 10 ether);

    bytes memory hopData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token0), uint256(10 ether)));

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 4 ether });
    inputs[1] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 6 ether });

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 10 ether,
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 10 ether,
      swapData: _signedSwapData(address(tokenX), address(token0), 10 ether, 10 ether, hopData)
    });

    (uint256 total0,) =
      harness.executePancakeWithInputs(address(router), address(token0), address(token1), inputs, 0, swaps);

    assertEq(total0, 10 ether, "merged duplicate seeds spent through one hop");
    assertEq(tokenX.balanceOf(address(harness)), 0, "combined seed fully consumed");
  }

  /// @dev Twin of test_executeWithInputs_revertsWhenInputHasNoConsumingHop.
  function test_executePancakeWithInputs_revertsWhenInputHasNoConsumingHop() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Dangling", "DGL");
    harness.setVaultToken(address(tokenX), true);
    tokenX.mint(address(harness), 10 ether);

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](1);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 10 ether });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.executePancakeWithInputs(
      address(router), address(token0), address(token1), inputs, 0, new ISharedPancakeV4Utils.SwapParams[](0)
    );
  }

  /// @dev Twin of test_executeWithInputs_revertsWhenInputNotFullyConsumed.
  function test_executePancakeWithInputs_revertsWhenInputNotFullyConsumed() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Source", "SRC");
    harness.setVaultToken(address(tokenX), true);
    tokenX.mint(address(harness), 10 ether);
    token0.mint(address(router), 6 ether);

    bytes memory hopData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token0), uint256(6 ether)));

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](1);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 10 ether });

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 6 ether, // leaves 4 ether of the seed unconsumed
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 6 ether,
      swapData: _signedSwapData(address(tokenX), address(token0), 6 ether, 6 ether, hopData)
    });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.executePancakeWithInputs(address(router), address(token0), address(token1), inputs, 0, swaps);
  }

  /// @dev Twin of test_executeWithInputs_revertsWhenHopOverdrawsSeededBudget.
  function test_executePancakeWithInputs_revertsWhenHopOverdrawsSeededBudget() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Source", "SRC");
    harness.setVaultToken(address(tokenX), true);
    tokenX.mint(address(harness), 20 ether);

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](1);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 10 ether });

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 11 ether, // exceeds the 10 ether seed
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 0,
      swapData: hex"01" // never reached — the budget check precedes signature verification
    });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.executePancakeWithInputs(address(router), address(token0), address(token1), inputs, 0, swaps);
  }

  /// @dev Twin of test_executeWithInputs_rejectsNonVaultTokenInput.
  function test_executePancakeWithInputs_rejectsNonVaultTokenInput() public {
    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Rogue", "RGE");
    tokenX.mint(address(harness), 10 ether);

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](1);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 10 ether });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    harness.executePancakeWithInputs(
      address(router), address(token0), address(token1), inputs, 0, new ISharedPancakeV4Utils.SwapParams[](0)
    );
  }

  /// @dev Twin of test_executeWithInputs_skimsGasFeeThenRequiresExactRemainderConsumption.
  function test_executePancakeWithInputs_skimsGasFeeThenRequiresExactRemainderConsumption() public {
    address gasFeeRecipient = makeAddr("gasFeeRecipient");
    configManager.setFeeRecipient(gasFeeRecipient);

    SharedPancakeV4SwapPipelineTestToken tokenX = new SharedPancakeV4SwapPipelineTestToken("Source", "SRC");
    harness.setVaultToken(address(tokenX), true);
    tokenX.mint(address(harness), 8 ether);
    token0.mint(address(router), 6 ether);

    bytes memory hopData =
      abi.encodeCall(SharedPancakeV4SwapPipelineRouter.swapAll, (address(tokenX), address(token0), uint256(6 ether)));

    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](1);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(tokenX)), amount: 8 ether });

    ISharedPancakeV4Utils.SwapParams[] memory swaps = new ISharedPancakeV4Utils.SwapParams[](1);
    swaps[0] = ISharedPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 6 ether, // = 8 ether minus the 25% skim
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 6 ether,
      swapData: _signedSwapData(address(tokenX), address(token0), 6 ether, 6 ether, hopData)
    });

    (uint256 total0,) = harness.executePancakeWithInputs(
      address(router),
      address(token0),
      address(token1),
      inputs,
      uint64(uint256(0x10000000000000000) / 4), // 25%
      swaps
    );

    assertEq(tokenX.balanceOf(gasFeeRecipient), 2 ether, "25% input gas fee skimmed to the recipient");
    assertEq(total0, 6 ether, "post-fee remainder swapped into total0");
    assertEq(tokenX.balanceOf(address(harness)), 0, "post-fee remainder fully consumed");
  }

  function _signedSwapData(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData
  ) internal returns (bytes memory) {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 swapNonce = bytes32(++nonce);
    bytes32 digest = SharedSwapDataSignature.hash(
      address(harness),
      signer,
      address(router),
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline,
      swapNonce
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
    return abi.encode(rawSwapData, address(harness), deadline, signer, swapNonce, abi.encodePacked(r, s, v));
  }
}
