// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedV4StrategyLib.sol";
import { ISharedV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

// ---------------------------------------------------------------------------
// v4utils-parity action events emitted by SharedV4StrategyLib: SwapAndMint,
// SwapAndIncrease, CompoundFees, DecreaseAndSwap, AdjustRange. The harness
// delegatecalls the lib's external entry points, so inside the lib
// `address(this)` is the harness (standing in for SharedVault) and the events
// surface at the harness address — exactly as they surface at the vault
// on-chain. No swap hops are encoded, so the pipeline passes input amounts
// through and no router/signature plumbing is needed; per-hop Swap events are
// covered in SharedV4SwapPipeline.t.sol.
// Twin: SharedPancakeV4StrategyEvents.t.sol (the libs are forks).
// ---------------------------------------------------------------------------

contract EvtV4Token {
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

contract EvtV4Permit2 {
  function approve(address, address, uint160, uint48) external { }
}

/// @dev Pool manager at a fixed 1:1 price, read by the lib via StateLibrary's extsload getSlot0.
contract EvtV4PoolManager {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  function extsload(bytes32) external pure returns (bytes32) {
    return bytes32(uint256(SQRT_PRICE_1_1));
  }

  function extsload(bytes32, uint256 nSlots) external pure returns (bytes32[] memory values) {
    values = new bytes32[](nSlots);
  }
}

/// @dev POSM mock for a hookless ±60-tick position at a 1:1 price. `modifyLiquidities` models
///      exactly what the event paths observe:
///        DECREASE_LIQUIDITY(liquidity == 0) — fee-sync collect: mints the staged fees to the caller
///        DECREASE_LIQUIDITY(liquidity > 0)  — principal out: mints the staged principal, burns liquidity
///        MINT_POSITION                      — consumes nextTokenId
///        INCREASE_LIQUIDITY                 — no-op (the lib quotes amounts itself)
contract EvtV4Posm {
  EvtV4Token internal token0;
  EvtV4Token internal token1;
  EvtV4PoolManager public immutable poolManagerMock;
  EvtV4Permit2 public immutable permit2Mock;

  uint256 public nextTokenId = 7;
  uint128 internal liquidity_;
  uint256 internal stagedFee0;
  uint256 internal stagedFee1;
  uint256 internal stagedPrincipal0;
  uint256 internal stagedPrincipal1;
  address internal positionOwner;

  constructor(EvtV4Token _token0, EvtV4Token _token1) {
    token0 = _token0;
    token1 = _token1;
    poolManagerMock = new EvtV4PoolManager();
    permit2Mock = new EvtV4Permit2();
  }

  function setPositionOwner(address owner) external {
    positionOwner = owner;
  }

  function setLiquidity(uint128 liquidity) external {
    liquidity_ = liquidity;
  }

  function stageFees(uint256 amount0, uint256 amount1) external {
    stagedFee0 = amount0;
    stagedFee1 = amount1;
  }

  function stagePrincipal(uint256 amount0, uint256 amount1) external {
    stagedPrincipal0 = amount0;
    stagedPrincipal1 = amount1;
  }

  function poolManager() external view returns (address) {
    return address(poolManagerMock);
  }

  function permit2() external view returns (address) {
    return address(permit2Mock);
  }

  function ownerOf(uint256) external view returns (address) {
    return positionOwner;
  }

  function getPositionLiquidity(uint256) external view returns (uint128) {
    return liquidity_;
  }

  function getPoolAndPositionInfo(uint256) public view returns (PoolKey memory key, PositionInfo info) {
    key.currency0 = Currency.wrap(address(token0));
    key.currency1 = Currency.wrap(address(token1));
    key.fee = 500;
    key.tickSpacing = 60;
    key.hooks = IHooks(address(0));
    info = PositionInfoLibrary.initialize(key, -60, 60);
  }

  function positionInfo(uint256 tokenId) external view returns (PositionInfo info) {
    (, info) = getPoolAndPositionInfo(tokenId);
  }

  function modifyLiquidities(bytes calldata data, uint256) external payable {
    (bytes memory actions, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));
    uint8 action = uint8(actions[0]);
    if (action == 0x01) {
      // DECREASE_LIQUIDITY param layout: (tokenId, liquidity, amount0Min, amount1Min, hookData)
      (, uint256 liquidity,,,) = abi.decode(params[0], (uint256, uint256, uint256, uint256, bytes));
      if (liquidity == 0) {
        if (stagedFee0 > 0) token0.mint(msg.sender, stagedFee0);
        if (stagedFee1 > 0) token1.mint(msg.sender, stagedFee1);
        stagedFee0 = 0;
        stagedFee1 = 0;
      } else {
        if (stagedPrincipal0 > 0) token0.mint(msg.sender, stagedPrincipal0);
        if (stagedPrincipal1 > 0) token1.mint(msg.sender, stagedPrincipal1);
        liquidity_ -= uint128(liquidity);
      }
    } else if (action == 0x02) {
      // MINT_POSITION
      nextTokenId++;
    }
    // INCREASE_LIQUIDITY (0x00): no-op
  }
}

/// @dev Zero performance fees so collected LP fees flow through the compound un-skimmed.
contract EvtV4ConfigManager {
  function platformFeeBasisPoint() external pure returns (uint16) {
    return 0;
  }

  function feeRecipient() external pure returns (address) {
    return address(0xFEE);
  }
}

/// @dev Delegatecall context standing in for SharedVault: drives the lib's external entry points so
///      events surface at this address, and implements the minimal ISharedVault surface the paths
///      consult (configManager / vaultOwner / vaultOwnerFeeBasisPoint / isVaultToken / weth).
contract EvtV4VaultHarness {
  address public configManager;
  address public vaultOwner = address(0xCC02);
  uint16 public vaultOwnerFeeBasisPoint = 0;
  mapping(address => bool) public isVaultToken;

  constructor(address _configManager) {
    configManager = _configManager;
  }

  function addVaultToken(address token) external {
    isVaultToken[token] = true;
  }

  function weth() external pure returns (address) {
    return address(0xBEEF);
  }

  function swapAndMint(address posm, bytes memory params) external {
    SharedV4StrategyLib.swapAndMintCalldata(address(0xD00D), posm, params);
  }

  function swapAndIncrease(address posm, uint256 tokenId, bytes memory params) external {
    SharedV4StrategyLib.swapAndIncreaseCalldata(address(0xD00D), posm, tokenId, params);
  }

  function executeInstruction(address posm, uint256 tokenId, ISharedV4Utils.Instructions memory instructions) external {
    SharedV4StrategyLib.executeInstructionBytes(address(0xD00D), posm, tokenId, abi.encode(instructions));
  }
}

contract SharedV4StrategyEventsTest is Test {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;
  uint256 internal constant TOKEN_ID = 1;

  EvtV4Token internal token0;
  EvtV4Token internal token1;
  EvtV4Posm internal posm;
  EvtV4VaultHarness internal harness;

  function setUp() public {
    token0 = new EvtV4Token("ET0");
    token1 = new EvtV4Token("ET1");
    harness = new EvtV4VaultHarness(address(new EvtV4ConfigManager()));
    harness.addVaultToken(address(token0));
    harness.addVaultToken(address(token1));
    posm = new EvtV4Posm(token0, token1);
    posm.setPositionOwner(address(harness));
    token0.mint(address(harness), 1000e18);
    token1.mint(address(harness), 1000e18);
  }

  /// @dev Identical quote to the lib's `_mintV4WithAmounts` / `_increaseV4WithAmounts` (same
  ///      TickMath + LiquidityAmounts imports), so expected event liquidity matches bit-for-bit.
  function _quotedLiquidity(uint256 amount0, uint256 amount1) internal pure returns (uint128) {
    return LiquidityAmounts.getLiquidityForAmounts(
      SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(-60), TickMath.getSqrtPriceAtTick(60), amount0, amount1
    );
  }

  /// @dev Mirrors the lib's consumed-amounts quote: getAmountsForLiquidity over the realized
  ///      liquidity at the execution price. The round-trip never exceeds the supplied amounts.
  function _quotedAmounts(uint128 liquidity) internal pure returns (uint256 amount0, uint256 amount1) {
    return LiquidityAmounts.getAmountsForLiquidity(
      SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(-60), TickMath.getSqrtPriceAtTick(60), liquidity
    );
  }

  function _poolKey() internal view returns (PoolKey memory key) {
    key.currency0 = Currency.wrap(address(token0));
    key.currency1 = Currency.wrap(address(token1));
    key.fee = 500;
    key.tickSpacing = 60;
    key.hooks = IHooks(address(0));
  }

  function _inputs(uint256 amount0, uint256 amount1) internal view returns (ISharedV4Utils.InputTokenParams[] memory) {
    ISharedV4Utils.InputTokenParams[] memory inputs = new ISharedV4Utils.InputTokenParams[](2);
    inputs[0] = ISharedV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: amount0 });
    inputs[1] = ISharedV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: amount1 });
    return inputs;
  }

  function test_v4_swapAndMint_emitsSwapAndMint() public {
    uint256 amount0 = 5e18;
    uint256 amount1 = 5e18;
    ISharedV4Utils.SwapAndMintParams memory p;
    p.posm = address(posm);
    p.poolKey = _poolKey();
    p.mintParams =
      ISharedV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.inputTokens = _inputs(amount0, amount1);
    p.sweepTokens = new Currency[](0);

    uint256 expectedTokenId = posm.nextTokenId();
    uint128 expectedLiquidity = _quotedLiquidity(amount0, amount1);
    (uint256 used0, uint256 used1) = _quotedAmounts(expectedLiquidity);
    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.SwapAndMint(address(posm), expectedTokenId, expectedLiquidity, used0, used1);
    harness.swapAndMint(address(posm), abi.encodeCall(ISharedV4Utils.swapAndMint, (p)));
  }

  function test_v4_swapAndIncrease_emitsSwapAndIncrease() public {
    uint256 amount0 = 4e18;
    uint256 amount1 = 6e18;
    ISharedV4Utils.SwapAndIncreaseParams memory p;
    p.posm = address(posm);
    p.tokenId = TOKEN_ID;
    p.increaseParams = ISharedV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.inputTokens = _inputs(amount0, amount1);
    p.sweepTokens = new Currency[](0);

    uint128 expectedLiquidity = _quotedLiquidity(amount0, amount1);
    (uint256 used0, uint256 used1) = _quotedAmounts(expectedLiquidity);
    // The supply is imbalanced: token0 limits the liquidity, so part of the offered token1 stays
    // idle and must NOT be reported by the event.
    assertLt(used1, amount1, "imbalanced increase must consume less token1 than offered");
    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.SwapAndIncrease(address(posm), TOKEN_ID, expectedLiquidity, used0, used1);
    harness.swapAndIncrease(address(posm), TOKEN_ID, abi.encodeCall(ISharedV4Utils.swapAndIncrease, (p)));
  }

  /// @dev v4utils parity: CompoundFees reports the position's TOTAL liquidity after the compound
  ///      (the mock's INCREASE is a no-op, so it stays at the staged 5_000) and the amounts the
  ///      added liquidity consumes, quoted at the execution price (zero performance fees
  ///      configured, so the full collected fees feed the increase quote).
  function test_v4_compound_emitsCompoundFees() public {
    posm.setLiquidity(5000);
    posm.stageFees(1e18, 2e18);

    ISharedV4Utils.CompoundFeesParams memory p;
    p.collectFeesHookData = "";
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.increaseParams = ISharedV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: 0 });

    (uint256 used0, uint256 used1) = _quotedAmounts(_quotedLiquidity(1e18, 2e18));
    assertLt(used1, 2e18, "imbalanced compound must consume less token1 than collected");
    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.CompoundFees(address(posm), TOKEN_ID, 5000, used0, used1);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedV4Utils.Instructions({ action: ISharedV4Utils.UtilActions.COMPOUND, params: abi.encode(p) })
    );
  }

  /// @dev `liquidity` reports the REQUESTED decrease and `token`/`amount` the swapDestToken with this
  ///      operation's proceeds in it (principal token1 here; no swaps, no fees staged).
  function test_v4_decreaseAndSwap_emitsDecreaseAndSwap() public {
    posm.setLiquidity(1_000_000);
    posm.stagePrincipal(3e18, 4e18);

    ISharedV4Utils.DecreaseAndSwapParams memory p;
    p.decreaseParams = ISharedV4Utils.DecreaseLiquidityParams({
      liquidity: 600_000, deadline: 0, amount0Min: 0, amount1Min: 0, hookData: ""
    });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.swapDestToken = Currency.wrap(address(token1));

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.DecreaseAndSwap(address(posm), TOKEN_ID, 600_000, Currency.wrap(address(token1)), 4e18);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedV4Utils.Instructions({ action: ISharedV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(p) })
    );
  }

  /// @dev A swapDestToken outside the vault token list earns no terminal-output allowance and
  ///      nothing can flow into it, so `amount` reports 0 (and the action itself must not revert).
  function test_v4_decreaseAndSwap_nonPoolDestToken_reportsZeroAmount() public {
    posm.setLiquidity(1_000_000);
    posm.stagePrincipal(3e18, 4e18);

    ISharedV4Utils.DecreaseAndSwapParams memory p;
    p.decreaseParams = ISharedV4Utils.DecreaseLiquidityParams({
      liquidity: 600_000, deadline: 0, amount0Min: 0, amount1Min: 0, hookData: ""
    });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.swapDestToken = Currency.wrap(address(0xDEAD));

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.DecreaseAndSwap(address(posm), TOKEN_ID, 600_000, Currency.wrap(address(0xDEAD)), 0);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedV4Utils.Instructions({ action: ISharedV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(p) })
    );
  }

  function test_v4_adjustRange_emitsAdjustRange() public {
    posm.setLiquidity(1_000_000);
    posm.stagePrincipal(3e18, 4e18);

    ISharedV4Utils.AdjustRangeParams memory p;
    p.collectFeesHookData = "";
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.mintParams =
      ISharedV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });

    uint256 expectedNewTokenId = posm.nextTokenId();
    uint128 expectedLiquidity = _quotedLiquidity(3e18, 4e18);
    (uint256 used0, uint256 used1) = _quotedAmounts(expectedLiquidity);
    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.AdjustRange(address(posm), TOKEN_ID, expectedNewTokenId, expectedLiquidity, used0, used1);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedV4Utils.Instructions({ action: ISharedV4Utils.UtilActions.ADJUST_RANGE, params: abi.encode(p) })
    );
  }

  /// @dev Regression (review finding): the event must report the amounts CONSUMED by the minted
  ///      liquidity, not the post-swap amounts OFFERED to the POSM. token0 limits this supply, so
  ///      most of the offered token1 stays idle and must not appear in the event.
  function test_v4_swapAndMint_imbalancedSupply_reportsConsumedNotOffered() public {
    uint256 offered0 = 1e18;
    uint256 offered1 = 5e18;
    ISharedV4Utils.SwapAndMintParams memory p;
    p.posm = address(posm);
    p.poolKey = _poolKey();
    p.mintParams =
      ISharedV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.inputTokens = _inputs(offered0, offered1);
    p.sweepTokens = new Currency[](0);

    uint128 expectedLiquidity = _quotedLiquidity(offered0, offered1);
    (uint256 used0, uint256 used1) = _quotedAmounts(expectedLiquidity);
    assertLt(used1, offered1, "the non-limiting side must not be reported in full");

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.SwapAndMint(address(posm), posm.nextTokenId(), expectedLiquidity, used0, used1);
    harness.swapAndMint(address(posm), abi.encodeCall(ISharedV4Utils.swapAndMint, (p)));
  }

  /// @dev Below-range mint ([60, 120] with the pool at tick 0): the position is entirely token0,
  ///      so the offered token1 is never consumed and the event must report amount1 == 0.
  function test_v4_swapAndMint_belowRange_reportsZeroToken1() public {
    uint256 offered0 = 2e18;
    uint256 offered1 = 3e18;
    ISharedV4Utils.SwapAndMintParams memory p;
    p.posm = address(posm);
    p.poolKey = _poolKey();
    p.mintParams =
      ISharedV4Utils.MintParams({ tickLower: 60, tickUpper: 120, minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.inputTokens = _inputs(offered0, offered1);
    p.sweepTokens = new Currency[](0);

    uint128 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
      SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(60), TickMath.getSqrtPriceAtTick(120), offered0, offered1
    );
    (uint256 used0, uint256 used1) = LiquidityAmounts.getAmountsForLiquidity(
      SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(60), TickMath.getSqrtPriceAtTick(120), expectedLiquidity
    );
    assertEq(used1, 0, "below-range mint consumes no token1");

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedV4Utils.SwapAndMint(address(posm), posm.nextTokenId(), expectedLiquidity, used0, used1);
    harness.swapAndMint(address(posm), abi.encodeCall(ISharedV4Utils.swapAndMint, (p)));
  }
}
