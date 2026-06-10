// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
  INonfungiblePositionManager
} from "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";

// ---------------------------------------------------------------------------
// Coverage for the previously-untested SharedAerodromeStrategy swap paths
// (review PR #163, finding L2): the aggregator hop reached via
// WITHDRAW_AND_COLLECT_AND_SWAP -> _swapForWithdraw -> _swap -> swapRouter.call,
// the runtime `isWhitelistedSwapRouter` kill-switch, and the balance-delta
// accounting / position-untracking that surrounds it. Also covers the L1 fix:
// a degenerate CHANGE_RANGE on an empty position must NOT revert.
//
// Every prior Aerodrome test drove these opTypes with EMPTY swapData, so the
// `swapRouter.call` branch, the InvalidSwapRouter revert, and the swap-output
// accounting were never exercised end-to-end before this file.
// ---------------------------------------------------------------------------

contract SwapPathToken {
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _symbol) {
    symbol = _symbol;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

/// @dev Minimal Aerodrome-shaped NFPM. `collect()` returns whatever is currently staged (and mints it to the
///      recipient), `decreaseLiquidity()` burns liquidity and re-stages the principal for the following
///      `collect()`. This models the two-collect WITHDRAW flow: first collect = fee sync, second = principal.
contract SwapPathNfpm {
  SwapPathToken public immutable token0;
  SwapPathToken public immutable token1;

  uint128 public liquidity;
  uint256 public pendingCollect0;
  uint256 public pendingCollect1;
  uint256 public principalOut0;
  uint256 public principalOut1;
  uint256 public mintCalls;
  uint256 public nextMintId = 777;
  address public positionOwner;
  uint256 public increased0;
  uint256 public increased1;
  bool public positionsReverts;

  constructor(SwapPathToken _token0, SwapPathToken _token1) {
    token0 = _token0;
    token1 = _token1;
  }

  function setLiquidity(uint128 _liquidity) external {
    liquidity = _liquidity;
  }

  /// @dev Owner reported for every tokenId; SWAP_AND_INCREASE requires the vault to own the position.
  function setPositionOwner(address owner) external {
    positionOwner = owner;
  }

  function ownerOf(uint256) external view returns (address) {
    return positionOwner;
  }

  /// @dev Stage the amounts the next `collect()` returns (used as the withdraw fee-sync slice).
  function stageCollect(uint256 amount0, uint256 amount1) external {
    pendingCollect0 = amount0;
    pendingCollect1 = amount1;
  }

  /// @dev Principal released by `decreaseLiquidity()` (re-staged for the subsequent `collect()`).
  function setPrincipalOut(uint256 amount0, uint256 amount1) external {
    principalOut0 = amount0;
    principalOut1 = amount1;
  }

  /// @dev Simulates a burned/nonexistent tokenId: the real NFPM's positions() reverts for those, and
  ///      the strategy's valuation try/catch must absorb it.
  function setPositionsRevert(bool reverts) external {
    positionsReverts = reverts;
  }

  function positions(uint256)
    external
    view
    returns (uint96, address, address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    require(!positionsReverts, "Invalid token ID");
    return (0, address(0), address(token0), address(token1), int24(60), int24(-60), int24(60), liquidity, 0, 0, 0, 0);
  }

  function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
    external
    returns (uint128 addedLiquidity, uint256 amount0, uint256 amount1)
  {
    amount0 = params.amount0Desired;
    amount1 = params.amount1Desired;
    if (amount0 > 0) token0.transferFrom(msg.sender, address(this), amount0);
    if (amount1 > 0) token1.transferFrom(msg.sender, address(this), amount1);
    increased0 += amount0;
    increased1 += amount1;
    addedLiquidity = uint128(amount0 + amount1);
    liquidity += addedLiquidity;
  }

  function collect(INonfungiblePositionManager.CollectParams calldata params)
    external
    returns (uint256 amount0, uint256 amount1)
  {
    amount0 = pendingCollect0;
    amount1 = pendingCollect1;
    pendingCollect0 = 0;
    pendingCollect1 = 0;
    if (amount0 > 0) token0.mint(params.recipient, amount0);
    if (amount1 > 0) token1.mint(params.recipient, amount1);
  }

  function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
    external
    returns (uint256 amount0, uint256 amount1)
  {
    require(params.liquidity <= liquidity, "decrease exceeds liquidity");
    liquidity -= params.liquidity;
    // Stage the principal so the strategy's immediately-following collect() releases it.
    pendingCollect0 = principalOut0;
    pendingCollect1 = principalOut1;
    return (principalOut0, principalOut1);
  }

  function mint(INonfungiblePositionManager.MintParams calldata params)
    external
    returns (uint256 tokenId, uint128 liq, uint256 amount0, uint256 amount1)
  {
    mintCalls++;
    tokenId = nextMintId;
    if (params.amount0Desired > 0) token0.transferFrom(msg.sender, address(this), params.amount0Desired);
    if (params.amount1Desired > 0) token1.transferFrom(msg.sender, address(this), params.amount1Desired);
    liq = uint128(params.amount0Desired + params.amount1Desired);
    return (tokenId, liq, params.amount0Desired, params.amount1Desired);
  }

  function factory() external pure returns (address) {
    return address(0);
  }
}

/// @dev Aggregator mock: pulls `amountIn` of `tokenIn` from the caller (the vault, which approved it inline)
///      and delivers `amountOut` of `tokenOut`. The strategy never inspects swapData, so the encoded call is
///      free-form — what matters is the realized balance delta, which the strategy measures itself.
contract SwapPathRouter {
  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    SwapPathToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    SwapPathToken(tokenOut).mint(msg.sender, amountOut);
  }

  function swapTo(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, address recipient) external {
    SwapPathToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    SwapPathToken(tokenOut).mint(recipient, amountOut);
  }
}

contract SwapPathVaultHarness {
  SharedConfigManager public configManager;
  address public vaultOwner;
  uint16 public vaultOwnerFeeBasisPoint;
  mapping(address => bool) public isVaultToken;

  constructor(SharedConfigManager _configManager, address _vaultOwner, uint16 _vaultOwnerFeeBasisPoint) {
    configManager = _configManager;
    vaultOwner = _vaultOwner;
    vaultOwnerFeeBasisPoint = _vaultOwnerFeeBasisPoint;
  }

  function addVaultToken(address token) external {
    isVaultToken[token] = true;
  }

  function executeStrategy(address strategy, bytes memory data)
    external
    returns (ISharedStrategy.PositionChange[] memory changes)
  {
    (bool ok, bytes memory result) = strategy.delegatecall(abi.encodeCall(ISharedStrategy.execute, (data)));
    if (!ok) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
    changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
  }

  /// @dev Mirrors SharedVault._withdraw's exit delegatecall so exitProportional can be driven directly.
  function exitStrategy(address strategy, address _nfpm, uint256 tokenId, uint256 shares, uint256 totalShares)
    external
    returns (ISharedStrategy.PositionChange[] memory changes)
  {
    (bool ok, bytes memory result) = strategy.delegatecall(
      abi.encodeCall(ISharedStrategy.exitProportional, (_nfpm, tokenId, shares, totalShares, 0, 0, 0))
    );
    if (!ok) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
    changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
  }

  function verifySignedSwapData(address, address, address, uint256, uint256, bytes calldata)
    external
    pure
    returns (bytes memory)
  {
    revert("vault verify should not be called by strategy");
  }
}

contract SharedAerodromeStrategySwapPathTest is Test {
  uint256 internal constant TOKEN_ID = 1;

  SwapPathToken internal token0;
  SwapPathToken internal token1;
  SwapPathNfpm internal nfpm;
  SwapPathRouter internal router;
  SwapPathVaultHarness internal vault;
  SharedConfigManager internal cm;
  SharedAerodromeStrategy internal strategy;

  address internal platformRecipient = address(0xBB01);
  address internal vaultOwner = address(0xBB02);
  address internal automator = address(0xBB03);
  uint256 internal swapDataSignerPk = 0x5A17;
  address internal swapDataSigner;
  uint256 internal swapDataNonce;

  function setUp() public {
    token0 = new SwapPathToken("ST0");
    token1 = new SwapPathToken("ST1");
    nfpm = new SwapPathNfpm(token0, token1);
    router = new SwapPathRouter();

    cm = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    address[] memory swapRouters = new address[](1);
    swapRouters[0] = address(router);
    swapDataSigner = vm.addr(swapDataSignerPk);
    address[] memory signers = new address[](1);
    signers[0] = swapDataSigner;
    // (owner, admins, whitelistedCallers, feeRecipient, platformBps, nfpms, swapRouters)
    cm.initialize(
      address(this), new address[](0), new address[](0), platformRecipient, 1000, nfpms, swapRouters, signers
    );

    vault = new SwapPathVaultHarness(cm, vaultOwner, 500);
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));

    // Strategy's immutable swapRouter is the whitelisted mock aggregator.
    strategy = new SharedAerodromeStrategy(address(router));
  }

  function _signedSwapData(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData
  ) internal returns (bytes memory) {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 nonce = bytes32(++swapDataNonce);
    bytes32 digest = SharedSwapDataSignature.hash(
      address(vault),
      swapDataSigner,
      address(router),
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline,
      nonce
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapDataSignerPk, digest);
    return abi.encode(rawSwapData, address(vault), deadline, swapDataSigner, nonce, abi.encodePacked(r, s, v));
  }

  // -------------------------------------------------------------------------
  // L2: WITHDRAW_AND_COLLECT_AND_SWAP drives a REAL aggregator swap
  // -------------------------------------------------------------------------

  /// @dev Full exit: decrease all liquidity (principal = 1000 t0 + 2000 t1), then swap the entire token0 leg
  ///      to the target token1 through the whitelisted router. Asserts (a) the swap actually executed via
  ///      balance deltas (router received token0, vault received the token1 output), and (b) the drained
  ///      position is untracked.
  function test_withdrawAndCollectAndSwap_fullExit_swapsToTargetAndUntracks() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0); // no accrued fees — keep the focus on the principal swap
    nfpm.setPrincipalOut(1000, 2000);

    uint256 amountIn = 1000; // token0 principal, swapped in full
    uint256 amountOut = 900; // token1 delivered by the router
    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), amountIn, amountOut));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max; // full-exit sentinel; capped to posLiquidity
    instructions.targetToken = address(token1);
    instructions.amountIn0 = amountIn; // signer-authorized swap amount (== full realized principal here)
    instructions.amountOut0Min = 800; // < amountOut, so the slippage gate passes with margin
    instructions.swapData0 = _signedSwapData(address(token0), address(token1), amountIn, 800, swapData0);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), data);

    // Swap executed: router pulled the full token0 principal, vault holds principal token1 + swap output.
    assertEq(token0.balanceOf(address(router)), amountIn, "router pulled token0 amountIn");
    assertEq(token0.balanceOf(address(vault)), 0, "vault token0 fully swapped out");
    assertEq(token1.balanceOf(address(vault)), 2000 + amountOut, "vault token1 = principal + swap output");

    // Full exit -> position untracked.
    assertEq(nfpm.liquidity(), 0, "position fully drained");
    assertEq(changes.length, 1, "single position change");
    assertEq(changes[0].isAdd, false, "removal change");
    assertEq(changes[0].tokenId, TOKEN_ID, "untracked tokenId");
    assertEq(changes[0].token0, address(token0), "change token0");
    assertEq(changes[0].token1, address(token1), "change token1");
  }

  /// @dev The swap must consume the signer-authorized `instructions.amountIn0` — NOT the on-chain
  ///      computed principal+fees `amount0`. The backend folds withdraw-liquidity slippage into amountIn0,
  ///      so it is intentionally smaller than the realized principal, and the SwapDataSignature digest is
  ///      bound to amountIn0. Before the fix `_swapForWithdraw` passed the computed amount0 to `_swap`, so
  ///      the digest reconstructed over amount0 (=1000) diverged from the signature over amountIn0 (=900)
  ///      and the withdraw reverted with InvalidSwapDataSignature. After the fix it swaps exactly amountIn0
  ///      and leaves the slippage-buffer remainder as vault token0.
  function test_withdrawAndCollectAndSwap_swapsSignedAmountInNotComputedAmount() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000); // realized amount0 = 1000, amount1 = 2000

    uint256 amountIn0 = 900; // backend's slippage-adjusted swap amount (< realized 1000)
    uint256 amountOut = 880; // token1 delivered for swapping 900 token0
    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), amountIn0, amountOut));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = amountIn0;
    instructions.amountOut0Min = 800;
    instructions.swapData0 = _signedSwapData(address(token0), address(token1), amountIn0, 800, swapData0);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    // Swap consumed exactly the signed amountIn0; the slippage-buffer remainder stays as vault token0.
    assertEq(token0.balanceOf(address(router)), amountIn0, "router pulled exactly amountIn0");
    assertEq(token0.balanceOf(address(vault)), 1000 - amountIn0, "vault keeps realized - amountIn0 remainder");
    assertEq(token1.balanceOf(address(vault)), 2000 + amountOut, "vault token1 = principal + swap output");
  }

  /// @dev Pooled-funds guard: `instructions.amountIn0` is both the signer's swap amount and the minAmount0
  ///      floor for the realized (decreased liquidity + collected fees). If the realized `amount0` lands
  ///      below the signed amountIn0 (a withdraw-slippage breach), the swap must NOT proceed and reach past
  ///      this withdraw into the rest of the pooled vault balance — it reverts with InvalidAmount.
  function test_withdrawAndCollectAndSwap_revertsWhenRealizedBelowSignedAmountIn() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(900, 2000); // realized amount0 = 900 < signed amountIn0 = 1000

    uint256 amountIn0 = 1000;
    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), amountIn0, uint256(900)));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = amountIn0;
    instructions.amountOut0Min = 800;
    instructions.swapData0 = _signedSwapData(address(token0), address(token1), amountIn0, 800, swapData0);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.executeStrategy(address(strategy), data);
  }

  /// @dev Symmetric token1 leg: with targetToken == token0, the token1 principal is swapped to token0 using
  ///      the signer-authorized `instructions.amountIn1` (bound into the digest), the token0 principal stays
  ///      as the target, and the amountIn1 slippage-buffer remainder stays as vault token1. Guards the other
  ///      half of the fix (`amount1 >= amountIn1` + swap amountIn1, not the computed amount1).
  function test_withdrawAndCollectAndSwap_swapsSignedAmountIn1ForToken1Leg() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(2000, 1000); // realized amount0 = 2000 (target), amount1 = 1000

    uint256 amountIn1 = 900; // backend's slippage-adjusted swap amount for the token1 leg (< realized 1000)
    uint256 amountOut = 880; // token0 delivered for swapping 900 token1
    bytes memory swapData1 =
      abi.encodeCall(SwapPathRouter.swap, (address(token1), address(token0), amountIn1, amountOut));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token0); // token0 is the target; token1 gets swapped into it
    instructions.amountIn1 = amountIn1;
    instructions.amountOut1Min = 800;
    instructions.swapData1 = _signedSwapData(address(token1), address(token0), amountIn1, 800, swapData1);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    assertEq(token1.balanceOf(address(router)), amountIn1, "router pulled exactly amountIn1");
    assertEq(token1.balanceOf(address(vault)), 1000 - amountIn1, "vault keeps realized - amountIn1 remainder");
    assertEq(token0.balanceOf(address(vault)), 2000 + amountOut, "vault token0 = principal + swap output");
  }

  function test_withdrawAndCollectAndSwap_revertsWhenReusingSignedSwapData() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), uint256(1000), uint256(900)));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 1000;
    instructions.amountOut0Min = 800;
    instructions.swapData0 = _signedSwapData(address(token0), address(token1), 1000, 800, swapData0);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.SwapDataSignatureAlreadyUsed.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_withdrawAndCollectAndSwap_revertsWhenUnsignedSwapRoutesOutputAwayFromVault() public {
    address attacker = address(0xA77A);
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    bytes memory swapData0 = abi.encodeCall(
      SwapPathRouter.swapTo, (address(token0), address(token1), uint256(1000), uint256(900), attacker)
    );

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 1000;
    instructions.amountOut0Min = 0;
    instructions.swapData0 = swapData0;

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert();
    vault.executeStrategy(address(strategy), data);
  }

  /// @dev The aggregator-swap slippage gate: when the router returns less than `amountOut0Min`, `_swap`
  ///      reverts with InsufficientOutput (this gate was never hit before because all prior tests used
  ///      empty swapData and skipped `_swap` entirely).
  function test_withdrawAndCollectAndSwap_revertsWhenSwapOutputBelowMin() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), uint256(1000), uint256(900)));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 1000;
    instructions.amountOut0Min = 1000; // > 900 actually delivered -> must revert
    instructions.swapData0 = _signedSwapData(address(token0), address(token1), 1000, 1000, swapData0);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_withdrawAndCollectAndSwap_revertsWhenEmptySwapDataHasMinOut() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 1000; // non-zero so _swap reaches the empty-swapData guard, not the amountIn==0 guard
    instructions.amountOut0Min = 1;
    instructions.swapData0 = "";

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_withdrawAndCollectAndSwap_revertsWhenTargetSideHasMinOut() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 0);

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token0);
    instructions.amountOut0Min = 1;

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_changeRange_revertsWhenTargetTokenIsNotPoolToken() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(0xDEAD);
    instructions.tickLower = -120;
    instructions.tickUpper = 120;

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.executeStrategy(address(strategy), data);
  }

  /// @dev The runtime kill-switch: even though the strategy's immutable swapRouter is fixed at deploy, a
  ///      swap-bearing instruction reverts with InvalidSwapRouter once the owner removes that router from the
  ///      ConfigManager whitelist. Proves the defense-in-depth re-check in `_swap` is wired and effective.
  function test_withdrawAndCollectAndSwap_revertsWhenSwapRouterDeWhitelisted() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000);

    // Owner revokes the (compromised/deprecated) aggregator.
    address[] memory toRevoke = new address[](1);
    toRevoke[0] = address(router);
    cm.setWhitelistSwapRouters(toRevoke, false);

    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), uint256(1000), uint256(900)));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 1000;
    instructions.swapData0 = swapData0;

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, address(router)));
    vault.executeStrategy(address(strategy), data);
  }

  // -------------------------------------------------------------------------
  // L1: degenerate CHANGE_RANGE on an empty position must not revert
  // -------------------------------------------------------------------------

  /// @dev A CHANGE_RANGE on a zero-liquidity, fee-less position yields (total0, total1) == (0, 0). Before the
  ///      L1 fix this reverted in NFPM.mint (cannot mint zero liquidity); now the strategy skips the mint and
  ///      untracks the empty source position instead. Asserts no revert, no mint, and a single removal change.
  function test_changeRange_emptyPosition_doesNotRevertAndUntracks() public {
    nfpm.setLiquidity(0); // empty position
    nfpm.stageCollect(0, 0); // no fees

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;
    instructions.liquidity = 0;
    instructions.targetToken = address(0); // no swap
    // tickLower == tickUpper == 0 keeps the existing range

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), data);

    assertEq(nfpm.mintCalls(), 0, "no mint attempted for empty position");
    assertEq(changes.length, 1, "single removal change");
    assertEq(changes[0].isAdd, false, "empty position untracked");
    assertEq(changes[0].tokenId, TOKEN_ID, "untracked tokenId");
  }

  // -------------------------------------------------------------------------
  // Review fix: COMPOUND_FEES with targetToken == address(0) performs NO swap,
  // so a caller-supplied amountOut*Min would otherwise be silently ignored.
  // _swapForCompound must now reject it, mirroring _swapForWithdraw.
  // -------------------------------------------------------------------------

  function test_compound_revertsWhenNoSwapTargetButAmountOut0MinSet() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);

    IV3Utils.Instructions memory instructions = _baseInstructions(); // COMPOUND_FEES, targetToken == address(0)
    instructions.amountOut0Min = 1; // stale slippage bound that no swap will honor

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_compound_revertsWhenNoSwapTargetButAmountOut1MinSet() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.amountOut1Min = 1;

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  // -------------------------------------------------------------------------
  // Mint/increase-side signed-amount guards (_swapAndPrepareAmounts /
  // _swapAndPrepareIncreaseAmounts) — twins of the SharedV3StrategySwapPath
  // tests; the two strategies fork the same branch logic.
  // -------------------------------------------------------------------------

  /// @dev swapSourceToken == token0: the signed token1-leg swap may consume at most `amount0`. A swap
  ///      amount above the provided budget must revert InvalidAmount BEFORE any router interaction —
  ///      otherwise the swap would reach past this operation into pooled vault token0.
  function test_swapAndMint_revertsWhenAmount0BelowSignedAmountIn1() public {
    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.swapSourceToken = address(token0);
    params.amount0 = 500;
    params.amountIn1 = 1000; // > amount0 budget

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.executeStrategy(address(strategy), _mintData(params));
  }

  /// @dev swapSourceToken == token1: mirrored budget guard for the token0 leg.
  function test_swapAndMint_revertsWhenAmount1BelowSignedAmountIn0() public {
    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.swapSourceToken = address(token1);
    params.amount1 = 500;
    params.amountIn0 = 1000; // > amount1 budget

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.executeStrategy(address(strategy), _mintData(params));
  }

  /// @dev Third-vault-token source: amountIn0 + amountIn1 must fit within the declared amount2 budget.
  function test_swapAndMint_thirdTokenSource_revertsWhenBudgetExceeded() public {
    SwapPathToken tokenX = new SwapPathToken("STX");
    vault.addVaultToken(address(tokenX));

    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.swapSourceToken = address(tokenX);
    params.amount2 = 1000;
    params.amountIn0 = 600;
    params.amountIn1 = 500; // 600 + 500 > 1000

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.executeStrategy(address(strategy), _mintData(params));
  }

  /// @dev A swap source that is not a vault token must be rejected — the two-leg swap branch would
  ///      otherwise move an untracked asset through the vault's swap path.
  function test_swapAndMint_thirdTokenSource_revertsWhenSourceNotVaultToken() public {
    SwapPathToken tokenX = new SwapPathToken("STX"); // NOT registered on the vault

    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.swapSourceToken = address(tokenX);
    params.amount2 = 1000;
    params.amountIn0 = 400;
    params.amountIn1 = 400;

    vm.prank(automator);
    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    vault.executeStrategy(address(strategy), _mintData(params));
  }

  /// @dev Happy path for the previously-untested third-token branch: both legs swap signed amounts of the
  ///      source vault token into the pool pair, and the mint consumes exactly the swap outputs.
  function test_swapAndMint_thirdTokenSource_swapsBothLegsAndMints() public {
    SwapPathToken tokenX = new SwapPathToken("STX");
    vault.addVaultToken(address(tokenX));
    tokenX.mint(address(vault), 2000);

    uint256 amountIn0 = 1000;
    uint256 amountIn1 = 1000;
    uint256 out0 = 600;
    uint256 out1 = 700;
    bytes memory swapData0 = abi.encodeCall(SwapPathRouter.swap, (address(tokenX), address(token0), amountIn0, out0));
    bytes memory swapData1 = abi.encodeCall(SwapPathRouter.swap, (address(tokenX), address(token1), amountIn1, out1));

    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.swapSourceToken = address(tokenX);
    params.amount2 = 2000;
    params.amountIn0 = amountIn0;
    params.amountOut0Min = out0;
    params.swapData0 = _signedSwapData(address(tokenX), address(token0), amountIn0, out0, swapData0);
    params.amountIn1 = amountIn1;
    params.amountOut1Min = out1;
    params.swapData1 = _signedSwapData(address(tokenX), address(token1), amountIn1, out1, swapData1);

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), _mintData(params));

    assertEq(tokenX.balanceOf(address(vault)), 0, "both legs consumed the tokenX budget");
    assertEq(tokenX.balanceOf(address(router)), 2000, "router pulled the signed amounts");
    assertEq(nfpm.mintCalls(), 1, "position minted");
    assertEq(token0.balanceOf(address(nfpm)), out0, "mint consumed the token0 swap output");
    assertEq(token1.balanceOf(address(nfpm)), out1, "mint consumed the token1 swap output");
    assertEq(changes.length, 1, "single position change");
    assertEq(changes[0].isAdd, true, "mint tracked");
    assertEq(changes[0].tokenId, 777, "tracked tokenId from the NFPM mint");
  }

  /// @dev Same budget guard on the increase path (_swapAndPrepareIncreaseAmounts).
  function test_swapAndIncrease_revertsWhenAmount0BelowSignedAmountIn1() public {
    nfpm.setPositionOwner(address(vault));

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = _baseIncreaseParams();
    params.swapSourceToken = address(token0);
    params.amount0 = 500;
    params.amountIn1 = 1000; // > amount0 budget

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.SWAP_AND_INCREASE),
      abi.encode(params, new address[](0), new uint256[](0), uint256(0))
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.executeStrategy(address(strategy), data);
  }

  /// @dev Dust shares: when floor(posLiquidity * shares / totalShares) == 0 the strategy must not
  ///      touch the position at all — no liquidity decrease, no collect, no PositionChange — so the
  ///      vault's withdraw pays such a withdrawer from idle balances only and the position stays
  ///      tracked for the remaining holders. Twin of SharedV3StrategySwapPath's test.
  function test_exitProportional_dustShares_leavesPositionUntouched() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1000, 2000); // would be released IF a decrease ran — it must not

    // 1 share of 10_000_000: liquidityToRemove = floor(1_000_000 / 10_000_000) = 0
    ISharedStrategy.PositionChange[] memory changes =
      vault.exitStrategy(address(strategy), address(nfpm), TOKEN_ID, 1, 10_000_000);

    assertEq(changes.length, 0, "no position change for dust shares");
    assertEq(nfpm.liquidity(), 1_000_000, "liquidity untouched");
    assertEq(token0.balanceOf(address(vault)), 0, "no token0 released");
    assertEq(token1.balanceOf(address(vault)), 0, "no token1 released");
  }

  function _mintData(IV3Utils.SwapAndMintParams memory params) internal pure returns (bytes memory) {
    return bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.SWAP_AND_MINT),
      abi.encode(params, new address[](0), new uint256[](0), uint256(0))
    );
  }

  function _baseMintParams() internal view returns (IV3Utils.SwapAndMintParams memory) {
    return IV3Utils.SwapAndMintParams({
      protocol: 0,
      nfpm: address(nfpm),
      token0: address(token0),
      token1: address(token1),
      fee: 0,
      tickSpacing: 60,
      tickLower: -60,
      tickUpper: 60,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: 0,
      amount1: 0,
      amount2: 0,
      recipient: address(vault),
      deadline: block.timestamp + 1,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      poolDeployer: address(0)
    });
  }

  function _baseIncreaseParams() internal view returns (IV3Utils.SwapAndIncreaseLiquidityParams memory) {
    return IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0,
      nfpm: address(nfpm),
      tokenId: TOKEN_ID,
      amount0: 0,
      amount1: 0,
      amount2: 0,
      recipient: address(vault),
      deadline: block.timestamp + 1,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      protocolFeeX64: 0,
      gasFeeX64: 0
    });
  }

  function _baseInstructions() internal view returns (IV3Utils.Instructions memory) {
    return IV3Utils.Instructions({
      whatToDo: IV3Utils.WhatToDo.COMPOUND_FEES,
      protocol: 0,
      targetToken: address(0),
      amountRemoveMin0: 0,
      amountRemoveMin1: 0,
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      tickLower: 0,
      tickUpper: 0,
      compoundFees: true,
      liquidity: 0,
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp + 1,
      recipient: address(vault),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
  }

  // -------------------------------------------------------------------------
  // COMPOUND_FEES with a swap target: the collected-fee swap leg and its two
  // guards (budget floor + target-side stale minOut). Mirrors
  // SharedV3StrategySwapPath.t.sol (fork twins).
  // -------------------------------------------------------------------------

  /// @dev Happy path: collected fees are perf-fee'd (platform 10% + owner 5%), the token0 remainder is
  ///      swapped toward the token1 target with signed swapData0, and the combined token1 total is
  ///      compounded into the position via increaseLiquidity. No position change is reported.
  function test_compound_withSwapTarget_swapsAndIncreasesLiquidity() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(1000, 2000);

    // Net after platform 10% (100/200) + owner 5% (50/100): 850 token0, 1700 token1.
    uint256 netFees0 = 850;
    uint256 swapOut = 800;
    bytes memory swapData0 =
      abi.encodeCall(SwapPathRouter.swap, (address(token0), address(token1), netFees0, swapOut));

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.targetToken = address(token1);
    instructions.amountIn0 = netFees0;
    instructions.amountOut0Min = swapOut;
    instructions.swapData0 = _signedSwapData(address(token0), address(token1), netFees0, swapOut, swapData0);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), data);

    assertEq(changes.length, 0, "compound keeps the tracked position");
    assertEq(token0.balanceOf(platformRecipient), 100, "platform fee token0");
    assertEq(token1.balanceOf(platformRecipient), 200, "platform fee token1");
    assertEq(token0.balanceOf(vaultOwner), 50, "owner fee token0");
    assertEq(token1.balanceOf(vaultOwner), 100, "owner fee token1");
    assertEq(token0.balanceOf(address(router)), netFees0, "router pulled the full net token0 fees");
    assertEq(nfpm.increased0(), 0, "nothing left on the token0 side");
    assertEq(nfpm.increased1(), 1700 + swapOut, "token1 fees + swap output compounded");
    assertEq(token0.balanceOf(address(vault)), 0, "no token0 residue");
    assertEq(token1.balanceOf(address(vault)), 0, "no token1 residue");
    assertEq(nfpm.liquidity(), 1_000_000 + 1700 + swapOut, "liquidity grew by the compounded amount");
  }

  /// @dev Budget floor: with targetToken == token1 the swap draws from the collected token0 fees, so
  ///      `amountIn0` may not exceed the net collected amount — the swap must not reach past this
  ///      operation's proceeds into other pooled vault balances.
  function test_compound_revertsWhenSwapBudgetExceedsCollectedFees() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(1000, 2000); // net token0 after fees: 850

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 851; // one over the net collected budget
    instructions.swapData0 = hex"01"; // never reached — budget check precedes the swap

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.executeStrategy(address(strategy), data);
  }

  /// @dev Target-side stale minOut: with targetToken == token1 no swap produces token1 "output", so a
  ///      nonzero amountOut1Min could never be honored and must revert instead of being ignored
  ///      (compound twin of the WITHDRAW_AND_COLLECT_AND_SWAP target-side guard).
  function test_compound_revertsWhenTargetSideHasMinOut() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(1000, 2000);

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.targetToken = address(token1);
    instructions.amountOut1Min = 1; // stale floor on the target side

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  // -------------------------------------------------------------------------
  // F3 input gas-fee skim on SWAP_AND_MINT / SWAP_AND_INCREASE (uniform with
  // the V4/Pancake strategies). Mirrors the V3 twin suite.
  // -------------------------------------------------------------------------

  /// @dev params.gasFeeX64 > 0 skims the Q64 fraction of BOTH input amounts to the config fee
  ///      recipient before the mint consumes the remainder.
  function test_swapAndMint_takesInputGasFeeBeforeMint() public {
    token0.mint(address(vault), 1000);
    token1.mint(address(vault), 2000);

    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.amount0 = 1000;
    params.amount1 = 2000;
    params.gasFeeX64 = uint64(1 << 62); // 25% in Q64 — under the 30% default config cap

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), _mintData(params));

    // 25% of each input goes to the fee recipient (cm.feeRecipient == platformRecipient).
    assertEq(token0.balanceOf(platformRecipient), 250, "gas fee skimmed from token0 input");
    assertEq(token1.balanceOf(platformRecipient), 500, "gas fee skimmed from token1 input");
    // The mint consumed the net remainder.
    assertEq(token0.balanceOf(address(nfpm)), 750, "mint consumed net token0");
    assertEq(token1.balanceOf(address(nfpm)), 1500, "mint consumed net token1");
    assertEq(changes.length, 1, "new position tracked");
    assertTrue(changes[0].isAdd, "position added");
  }

  /// @dev The mint-path gas fee is validated against the shared config cap (default 30%): an
  ///      over-cap fee must revert InvalidGasFeeX64 before any token movement.
  function test_swapAndMint_revertsWhenGasFeeExceedsConfigCap() public {
    token0.mint(address(vault), 1000);
    token1.mint(address(vault), 2000);

    IV3Utils.SwapAndMintParams memory params = _baseMintParams();
    params.amount0 = 1000;
    params.amount1 = 2000;
    params.gasFeeX64 = uint64((uint256(2) << 64) / 5); // 40% > 30% default cap

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidGasFeeX64.selector);
    vault.executeStrategy(address(strategy), _mintData(params));
  }

  /// @dev Same F3 skim on the SWAP_AND_INCREASE input side.
  function test_swapAndIncrease_takesInputGasFeeBeforeIncrease() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.setPositionOwner(address(vault));
    token0.mint(address(vault), 1000);
    token1.mint(address(vault), 2000);

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = _baseIncreaseParams();
    params.amount0 = 1000;
    params.amount1 = 2000;
    params.gasFeeX64 = uint64(1 << 62); // 25%

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.SWAP_AND_INCREASE),
      abi.encode(params, new address[](0), new uint256[](0), uint256(0))
    );

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), data);

    assertEq(changes.length, 0, "increase reports no position change");
    assertEq(token0.balanceOf(platformRecipient), 250, "gas fee skimmed from token0 input");
    assertEq(token1.balanceOf(platformRecipient), 500, "gas fee skimmed from token1 input");
    assertEq(nfpm.increased0(), 750, "net token0 added to the position");
    assertEq(nfpm.increased1(), 1500, "net token1 added to the position");
  }

  // -------------------------------------------------------------------------
  // exitProportional zero-liquidity early exit + burned-NFT valuation zeros.
  // Mirrors the V3 twin suite.
  // -------------------------------------------------------------------------

  /// @dev A tracked position whose liquidity is already zero must exit as a pure removal change —
  ///      withdraw flows untrack it instead of reverting in the NFPM on a zero-liquidity decrease.
  function test_exitProportional_zeroLiquidityPosition_returnsRemovalChange() public {
    nfpm.setLiquidity(0);

    ISharedStrategy.PositionChange[] memory changes =
      vault.exitStrategy(address(strategy), address(nfpm), TOKEN_ID, 5, 10);

    assertEq(changes.length, 1, "single change");
    assertEq(changes[0].isAdd, false, "removal change");
    assertEq(changes[0].tokenId, TOKEN_ID, "untracked tokenId");
    assertEq(token0.balanceOf(address(vault)), 0, "no token0 released");
    assertEq(token1.balanceOf(address(vault)), 0, "no token1 released");
  }

  /// @dev positions() reverts for burned/nonexistent tokenIds on the real NFPM. The valuation
  ///      try/catch must absorb that and report zero value — a revert here would brick
  ///      getTotalBalances (and with it deposits/withdrawals) for the whole vault.
  function test_getPositionAmounts_returnsZerosForBurnedNft() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.setPositionsRevert(true);

    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(address(nfpm), TOKEN_ID);
    assertEq(amount0, 0, "burned NFT values to zero (amount0)");
    assertEq(amount1, 0, "burned NFT values to zero (amount1)");

    (uint256 principal0, uint256 principal1) = strategy.getPositionPrincipalAmounts(address(nfpm), TOKEN_ID);
    assertEq(principal0, 0, "burned NFT principal zero (token0)");
    assertEq(principal1, 0, "burned NFT principal zero (token1)");

    (uint256 t0, uint256 t1, uint256 p0, uint256 p1) = strategy.getPositionAmountsSplit(address(nfpm), TOKEN_ID);
    assertEq(t0 + t1 + p0 + p1, 0, "burned NFT split values to zero");
  }
}
