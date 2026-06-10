// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";
import { SharedV4SwapPipeline } from "../../contracts/shared-vault/libraries/SharedV4SwapPipeline.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

contract SharedV4SwapPipelineTestToken is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract SharedV4SwapPipelineBalanceTrapToken {
  error BalanceOfCalled();

  function balanceOf(address) external pure returns (uint256) {
    revert BalanceOfCalled();
  }
}

contract SharedV4SwapPipelineConfigManager {
  address public router;
  address public signer;

  constructor(address _router, address _signer) {
    router = _router;
    signer = _signer;
  }

  function isWhitelistedSwapRouter(address account) external view returns (bool) {
    return account == router;
  }

  function isWhitelistedSigner(address account) external view returns (bool) {
    return account == signer;
  }
}

contract SharedV4SwapPipelineRouter {
  function swapAll(address tokenIn, address tokenOut, uint256 amountOut) external {
    uint256 amountIn = ERC20(tokenIn).allowance(msg.sender, address(this));
    ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    ERC20(tokenOut).transfer(msg.sender, amountOut);
  }
}

contract SharedV4SwapPipelineHarness {
  address public immutable weth;
  ISharedConfigManager public immutable configManager;

  constructor(address _configManager, address _weth) {
    configManager = ISharedConfigManager(_configManager);
    weth = _weth;
  }

  function execute(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    return SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, swapParams);
  }
}

contract SharedV4SwapPipelineTest is Test {
  uint256 internal constant SIGNER_PK = 0xA11CE;

  SharedV4SwapPipelineTestToken internal token0;
  SharedV4SwapPipelineTestToken internal token1;
  SharedV4SwapPipelineRouter internal router;
  SharedV4SwapPipelineHarness internal harness;
  address internal signer;
  uint256 internal nonce;

  function setUp() public {
    signer = vm.addr(SIGNER_PK);
    token0 = new SharedV4SwapPipelineTestToken("Token 0", "TK0");
    token1 = new SharedV4SwapPipelineTestToken("Token 1", "TK1");
    router = new SharedV4SwapPipelineRouter();
    SharedV4SwapPipelineConfigManager configManager = new SharedV4SwapPipelineConfigManager(address(router), signer);
    harness = new SharedV4SwapPipelineHarness(address(configManager), address(token0));
  }

  // -------------------------------------------------------------------------
  // Signature-bound amountIn. The pipeline must pass `swapParam.amountIn` to
  // SharedSwapDataSignature.verify VERBATIM — never an on-chain computed
  // balance. The backend folds withdraw-liquidity slippage into the signed
  // amount, so realized totals legitimately exceed it and the remainder stays
  // in the returned totals. `amountIn == 0` means "no swap for this hop" — it
  // is NOT resolved to the available balance. Mirrors the V3/Aerodrome
  // _swapForWithdraw signed-amount fix (SharedV3StrategySwapPath.t.sol).
  // -------------------------------------------------------------------------

  /// @dev Realized runtime amount (10.5e) exceeds the backend's slippage-adjusted signed amount (10e).
  ///      The hop must approve/swap exactly the signed amount — the digest binds it — and the
  ///      slippage-buffer remainder must stay in total0.
  function test_execute_swapsSignedParamAmountNotComputedBalance() public {
    uint256 runtimeAmount = 10.5 ether; // realized withdraw proceeds
    uint256 signedAmountIn = 10 ether; // backend folded withdraw-liquidity slippage into this
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: signedAmountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), signedAmountIn, amountOut, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);

    assertEq(token0.balanceOf(address(router)), signedAmountIn, "router pulled exactly the signed amountIn");
    assertEq(total0, runtimeAmount - signedAmountIn, "slippage-buffer remainder stays in total0");
    assertEq(total1, amountOut, "swap output credited to total1");
    assertEq(token0.balanceOf(address(harness)), runtimeAmount - signedAmountIn, "harness keeps the remainder");
    assertEq(token1.balanceOf(address(harness)), amountOut, "harness received the swap output");
  }

  /// @dev A signature over the computed runtime balance (the old resolved-amount behavior) must NOT
  ///      verify when `swapParam.amountIn` differs — proves the digest is reconstructed from the
  ///      param amount, not from whatever the vault happens to hold.
  function test_execute_rejectsSignatureBoundToComputedBalance() public {
    uint256 runtimeAmount = 10.5 ether;
    uint256 signedAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: signedAmountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmount, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  /// @dev Pooled-funds floor (twin of the V3/Aerodrome `amount0 >= amountIn0` guard): when the
  ///      realized total cannot cover the signed amountIn (a withdraw-slippage breach), the hop must
  ///      revert InvalidAmount rather than reach past this operation's proceeds.
  function test_execute_revertsWhenSignedAmountExceedsRuntimeBalance() public {
    uint256 runtimeAmount = 9 ether; // realized < signed
    uint256 signedAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: signedAmountIn,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), signedAmountIn, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  /// @dev `amountIn == 0` means "no swap for this hop" — NOT "swap the full available balance". The
  ///      hop must be skipped without touching the router, even when the swapData carries a valid
  ///      signature over the runtime balance (which the removed zero-sentinel would have resolved,
  ///      verified, and executed).
  function test_execute_zeroAmountInSkipsSwapInsteadOfResolvingToBalance() public {
    uint256 runtimeAmount = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 0,
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmount, 0, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);

    assertEq(total0, runtimeAmount, "total0 untouched by the skipped hop");
    assertEq(total1, 0, "no output credited");
    assertEq(token0.balanceOf(address(router)), 0, "router never called");
    assertEq(token0.balanceOf(address(harness)), runtimeAmount, "harness keeps its token0");
  }

  /// @dev A zero-amountIn hop performs no swap, so a non-zero `amountOutMin` is a stale slippage
  ///      floor that would be silently ignored — it must revert InsufficientOutput (mirrors the
  ///      strategies' no-swap amountOutMin guards).
  function test_execute_zeroAmountInWithAmountOutMinReverts() public {
    uint256 runtimeAmount = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmount);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmount, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  /// @dev The only way to reach _swap's no-op guard with a POSITIVE amountIn is an empty-swapData hop
  ///      (zero-amountIn hops short-circuit earlier in _run). With amountOutMin == 0 the hop must be a
  ///      tolerated no-op: no signature check, no router call, and the amount stays in the totals.
  function test_execute_emptySwapDataWithPositiveAmountInIsNoOp() public {
    uint256 runtimeAmount = 10 ether;
    token0.mint(address(harness), runtimeAmount);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 3 ether, // covered by total0, but the hop carries no calldata
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 0,
      swapData: ""
    });

    (uint256 total0, uint256 total1) =
      harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);

    assertEq(total0, runtimeAmount, "dataless hop leaves total0 untouched");
    assertEq(total1, 0, "no output credited");
    assertEq(token0.balanceOf(address(harness)), runtimeAmount, "no tokens moved");
  }

  /// @dev The revert half of the same guard: an empty-swapData hop with a non-zero amountOutMin is a
  ///      stale slippage floor no swap will honor — it must revert instead of being skipped.
  function test_execute_emptySwapDataWithPositiveAmountInAndMinOutReverts() public {
    uint256 runtimeAmount = 10 ether;
    token0.mint(address(harness), runtimeAmount);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 3 ether,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1,
      swapData: ""
    });

    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    harness.execute(address(router), address(token0), address(token1), runtimeAmount, 0, swaps);
  }

  function test_execute_rejectsBadSignatureBeforeBalanceSnapshots() public {
    SharedV4SwapPipelineBalanceTrapToken trapToken = new SharedV4SwapPipelineBalanceTrapToken();
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(trapToken), address(token1), uint256(1 ether)));

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(trapToken)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1 ether,
      swapData: abi.encode(rawSwapData, address(harness), block.timestamp + 1 hours, signer, bytes32("bad"), bytes(""))
    });

    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    harness.execute(address(router), address(trapToken), address(token1), 1 ether, 0, swaps);
  }

  // -------------------------------------------------------------------------
  // Reachability guards (_isSwapInputAllowed / _isSwapOutputAllowed) and the
  // intermediate virtual ledger. Integration covers the strategy-level wiring;
  // these pin the lib's own negative cases directly.
  // -------------------------------------------------------------------------

  /// @dev A hop whose tokenIn is neither a pool token nor a PRIOR hop's output is unreachable: the
  ///      pipeline would have no tracked balance to draw from, so it must revert InvalidPoolTokens
  ///      before resolving amounts or touching the router.
  function test_execute_rejectsUnreachableInputToken() public {
    SharedV4SwapPipelineTestToken tokenX = new SharedV4SwapPipelineTestToken("Intermediate", "TKX");

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 0,
      swapData: hex"01" // never reached — reachability check precedes signature verification
    });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    harness.execute(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev A hop whose tokenOut is neither a pool token nor consumed by a LATER hop would strand value
  ///      outside the (token0, token1) totals the caller books — it must revert InvalidPoolTokens.
  function test_execute_rejectsUnreachableOutputToken() public {
    SharedV4SwapPipelineTestToken tokenX = new SharedV4SwapPipelineTestToken("Stranded", "TKX");

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(tokenX)),
      amountOutMin: 0,
      swapData: hex"01"
    });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    harness.execute(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev Currency.wrap(address(0)) normalizes to the vault's WETH; when that WETH itself resolves to
  ///      address(0) (no wrapped-native configured), `_isSwapOutputAllowed` must reject the hop rather
  ///      than treat the zero address as a trackable intermediate.
  function test_execute_rejectsZeroAddressNormalizedOutput() public {
    SharedV4SwapPipelineConfigManager configManager = new SharedV4SwapPipelineConfigManager(address(router), signer);
    SharedV4SwapPipelineHarness zeroWethHarness = new SharedV4SwapPipelineHarness(address(configManager), address(0));

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(0)),
      amountOutMin: 0,
      swapData: hex"01"
    });

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    zeroWethHarness.execute(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev Reachability admits an intermediate as long as SOME later hop consumes it, but the virtual
  ///      ledger requires every intermediate balance to net to exactly zero after the loop. A second
  ///      hop that consumes only part of the intermediate passes reachability and must then fail the
  ///      final ledger check with InvalidAmount.
  function test_execute_revertsWhenIntermediatePartiallyConsumed() public {
    SharedV4SwapPipelineTestToken tokenX = new SharedV4SwapPipelineTestToken("Intermediate", "TKX");
    uint256 intermediateOut = 5 ether;
    uint256 partialIn = 2 ether;
    uint256 finalOut = 1 ether;

    token0.mint(address(harness), 10 ether);
    tokenX.mint(address(router), intermediateOut);
    token1.mint(address(router), finalOut);

    bytes memory hop1Data =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(tokenX), intermediateOut));
    bytes memory hop2Data =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(tokenX), address(token1), finalOut));

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](2);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 10 ether,
      tokenOut: Currency.wrap(address(tokenX)),
      amountOutMin: intermediateOut,
      swapData: _signedSwapData(address(token0), address(tokenX), 10 ether, intermediateOut, hop1Data)
    });
    swaps[1] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: partialIn, // leaves 3 ether of tokenX in the ledger
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: finalOut,
      swapData: _signedSwapData(address(tokenX), address(token1), partialIn, finalOut, hop2Data)
    });

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    harness.execute(address(router), address(token0), address(token1), 10 ether, 0, swaps);
  }

  /// @dev Positive control for both guards: token0 -> intermediate -> token1, with the second hop
  ///      consuming the full tracked intermediate balance via its explicit signed amountIn. The
  ///      ledger nets to zero and the output is credited to total1.
  function test_execute_multiHopThroughIntermediate_succeeds() public {
    SharedV4SwapPipelineTestToken tokenX = new SharedV4SwapPipelineTestToken("Intermediate", "TKX");
    uint256 intermediateOut = 5 ether;
    uint256 finalOut = 4 ether;

    token0.mint(address(harness), 10 ether);
    tokenX.mint(address(router), intermediateOut);
    token1.mint(address(router), finalOut);

    bytes memory hop1Data =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(tokenX), intermediateOut));
    bytes memory hop2Data =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(tokenX), address(token1), finalOut));

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](2);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 10 ether,
      tokenOut: Currency.wrap(address(tokenX)),
      amountOutMin: intermediateOut,
      swapData: _signedSwapData(address(token0), address(tokenX), 10 ether, intermediateOut, hop1Data)
    });
    swaps[1] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(tokenX)),
      amountIn: intermediateOut, // explicit signed amount: hop 1's full output (the digest binds it)
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: finalOut,
      swapData: _signedSwapData(address(tokenX), address(token1), intermediateOut, finalOut, hop2Data)
    });

    (uint256 total0, uint256 total1) =
      harness.execute(address(router), address(token0), address(token1), 10 ether, 0, swaps);

    assertEq(total0, 0, "token0 fully consumed by hop 1");
    assertEq(total1, finalOut, "hop 2 output credited to total1");
    assertEq(tokenX.balanceOf(address(harness)), 0, "no stranded intermediate balance");
    assertEq(token1.balanceOf(address(harness)), finalOut, "harness holds the final output");
  }

  /// @dev A self-swap hop (tokenIn == tokenOut) passes reachability (both sides are pool tokens) but
  ///      must fail `_swap`'s explicit guard with InvalidOperation BEFORE signature verification —
  ///      otherwise the output-delta accounting would double-count the unchanged balance. Unsigned
  ///      swapData proves the guard fires first.
  function test_execute_rejectsIdenticalTokenHop() public {
    token0.mint(address(harness), 1 ether);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 1 ether,
      tokenOut: Currency.wrap(address(token0)),
      amountOutMin: 0,
      swapData: hex"01" // never verified — the identical-token guard precedes signature checking
    });

    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    harness.execute(address(router), address(token0), address(token1), 1 ether, 0, swaps);
  }

  /// @dev The router-whitelist check is gated on `swaps.length > 0` — a zero-swap call must skip it
  ///      entirely (no configManager read) and pass the input amounts through untouched. Pins the
  ///      lazy-validation contract: strategies may thread ANY router address when no hop runs.
  function test_execute_skipsRouterWhitelistWhenNoSwaps() public {
    address unWhitelistedRouter = address(0xBAD);
    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](0);

    (uint256 total0, uint256 total1) =
      harness.execute(unWhitelistedRouter, address(token0), address(token1), 3 ether, 7 ether, swaps);

    assertEq(total0, 3 ether, "amount0 passes through untouched");
    assertEq(total1, 7 ether, "amount1 passes through untouched");
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
