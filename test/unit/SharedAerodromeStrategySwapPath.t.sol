// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager } from "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";

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
    if (allowance[from][msg.sender] != type(uint256).max) {
      allowance[from][msg.sender] -= amount;
    }
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

  constructor(SwapPathToken _token0, SwapPathToken _token1) {
    token0 = _token0;
    token1 = _token1;
  }

  function setLiquidity(uint128 _liquidity) external {
    liquidity = _liquidity;
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

  function positions(
    uint256
  )
    external
    view
    returns (uint96, address, address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    return (0, address(0), address(token0), address(token1), int24(60), int24(-60), int24(60), liquidity, 0, 0, 0, 0);
  }

  function collect(
    INonfungiblePositionManager.CollectParams calldata params
  ) external returns (uint256 amount0, uint256 amount1) {
    amount0 = pendingCollect0;
    amount1 = pendingCollect1;
    pendingCollect0 = 0;
    pendingCollect1 = 0;
    if (amount0 > 0) token0.mint(params.recipient, amount0);
    if (amount1 > 0) token1.mint(params.recipient, amount1);
  }

  function decreaseLiquidity(
    INonfungiblePositionManager.DecreaseLiquidityParams calldata params
  ) external returns (uint256 amount0, uint256 amount1) {
    require(params.liquidity <= liquidity, "decrease exceeds liquidity");
    liquidity -= params.liquidity;
    // Stage the principal so the strategy's immediately-following collect() releases it.
    pendingCollect0 = principalOut0;
    pendingCollect1 = principalOut1;
    return (principalOut0, principalOut1);
  }

  function mint(
    INonfungiblePositionManager.MintParams calldata params
  ) external returns (uint256 tokenId, uint128 liq, uint256 amount0, uint256 amount1) {
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

  function executeStrategy(
    address strategy,
    bytes memory data
  ) external returns (ISharedStrategy.PositionChange[] memory changes) {
    (bool ok, bytes memory result) = strategy.delegatecall(abi.encodeCall(ISharedStrategy.execute, (data)));
    if (!ok) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
    changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
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
    // (owner, admins, whitelistedCallers, feeRecipient, platformBps, nfpms, swapRouters)
    cm.initialize(address(this), new address[](0), new address[](0), platformRecipient, 1_000, nfpms, swapRouters);

    vault = new SwapPathVaultHarness(cm, vaultOwner, 500);
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));

    // Strategy's immutable swapRouter is the whitelisted mock aggregator.
    strategy = new SharedAerodromeStrategy(address(router));
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
    nfpm.setPrincipalOut(1_000, 2_000);

    uint256 amountIn = 1_000; // token0 principal, swapped in full
    uint256 amountOut = 900; // token1 delivered by the router
    bytes memory swapData0 = abi.encodeCall(
      SwapPathRouter.swap,
      (address(token0), address(token1), amountIn, amountOut)
    );

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max; // full-exit sentinel; capped to posLiquidity
    instructions.targetToken = address(token1);
    instructions.amountOut0Min = 800; // < amountOut, so the slippage gate passes with margin
    instructions.swapData0 = swapData0;

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), TOKEN_ID, instructions)
    );

    vm.prank(automator);
    ISharedStrategy.PositionChange[] memory changes = vault.executeStrategy(address(strategy), data);

    // Swap executed: router pulled the full token0 principal, vault holds principal token1 + swap output.
    assertEq(token0.balanceOf(address(router)), amountIn, "router pulled token0 amountIn");
    assertEq(token0.balanceOf(address(vault)), 0, "vault token0 fully swapped out");
    assertEq(token1.balanceOf(address(vault)), 2_000 + amountOut, "vault token1 = principal + swap output");

    // Full exit -> position untracked.
    assertEq(nfpm.liquidity(), 0, "position fully drained");
    assertEq(changes.length, 1, "single position change");
    assertEq(changes[0].isAdd, false, "removal change");
    assertEq(changes[0].tokenId, TOKEN_ID, "untracked tokenId");
    assertEq(changes[0].token0, address(token0), "change token0");
    assertEq(changes[0].token1, address(token1), "change token1");
  }

  /// @dev The aggregator-swap slippage gate: when the router returns less than `amountOut0Min`, `_swap`
  ///      reverts with InsufficientOutput (this gate was never hit before because all prior tests used
  ///      empty swapData and skipped `_swap` entirely).
  function test_withdrawAndCollectAndSwap_revertsWhenSwapOutputBelowMin() public {
    nfpm.setLiquidity(1_000_000);
    nfpm.stageCollect(0, 0);
    nfpm.setPrincipalOut(1_000, 2_000);

    bytes memory swapData0 = abi.encodeCall(
      SwapPathRouter.swap,
      (address(token0), address(token1), uint256(1_000), uint256(900))
    );

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
    instructions.amountOut0Min = 1_000; // > 900 actually delivered -> must revert
    instructions.swapData0 = swapData0;

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
    nfpm.setPrincipalOut(1_000, 2_000);

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
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
    nfpm.setPrincipalOut(1_000, 0);

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
    nfpm.setPrincipalOut(1_000, 2_000);

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
    nfpm.setPrincipalOut(1_000, 2_000);

    // Owner revokes the (compromised/deprecated) aggregator.
    address[] memory toRevoke = new address[](1);
    toRevoke[0] = address(router);
    cm.setWhitelistSwapRouters(toRevoke, false);

    bytes memory swapData0 = abi.encodeCall(
      SwapPathRouter.swap,
      (address(token0), address(token1), uint256(1_000), uint256(900))
    );

    IV3Utils.Instructions memory instructions = _baseInstructions();
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.liquidity = type(uint128).max;
    instructions.targetToken = address(token1);
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

  function _baseInstructions() internal view returns (IV3Utils.Instructions memory) {
    return
      IV3Utils.Instructions({
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
}
