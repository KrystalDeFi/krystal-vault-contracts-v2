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

  function test_execute_rejectsZeroSentinelSignatureWhenRuntimeAmountIsNonZero() public {
    uint256 runtimeAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmountIn);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), 0, amountOut, rawSwapData)
    });

    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    harness.execute(address(router), address(token0), address(token1), runtimeAmountIn, 0, swaps);
  }

  function test_execute_acceptsZeroSentinelWhenSignatureIsBoundToRuntimeAmount() public {
    uint256 runtimeAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmountIn);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), runtimeAmountIn, amountOut, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.execute(address(router), address(token0), address(token1), runtimeAmountIn, 0, swaps);

    assertEq(total0, 0, "swap-all consumed runtime token0 balance");
    assertEq(total1, amountOut, "swap output credited to token1 total");
    assertEq(token0.balanceOf(address(harness)), 0, "harness token0 spent");
    assertEq(token1.balanceOf(address(harness)), amountOut, "harness received token1");
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

  /// @dev Positive control for both guards: token0 -> intermediate -> token1, with the second hop's
  ///      zero-sentinel resolving to the full tracked intermediate balance. The ledger nets to zero
  ///      and the output is credited to total1.
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
      amountIn: 0, // zero-sentinel: full tracked intermediate balance (5 ether), signed as such
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
