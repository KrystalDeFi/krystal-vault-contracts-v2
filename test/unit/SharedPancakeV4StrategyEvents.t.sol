// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedPancakeV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedPancakeV4StrategyLib.sol";
import { ISharedPancakeV4Utils } from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";

import { Currency } from "infinity-core/src/types/Currency.sol";
import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { PoolId } from "infinity-core/src/types/PoolId.sol";
import { IHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

// ---------------------------------------------------------------------------
// v4utils-parity action events emitted by SharedPancakeV4StrategyLib:
// SwapAndMint, SwapAndIncrease, CompoundFees, DecreaseAndSwap, AdjustRange.
// Twin of SharedV4StrategyEvents.t.sol (the libs are forks); per-hop Swap
// events are covered in SharedPancakeV4SwapPipeline.t.sol.
// ---------------------------------------------------------------------------

contract EvtPancakeToken {
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

contract EvtPancakePermit2 {
  function approve(address, address, uint160, uint48) external { }
}

/// @dev CL pool manager at a fixed 1:1 price; the Pancake lib calls getSlot0 DIRECTLY (no extsload).
contract EvtPancakePoolManager {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  function getSlot0(PoolId) external pure returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
    return (SQRT_PRICE_1_1, 0, 0, 0);
  }
}

/// @dev CL POSM mock for a hookless ±60-tick position at a 1:1 price. `modifyLiquidities` models
///      exactly what the event paths observe (see the Uniswap V4 twin for the action semantics).
contract EvtPancakePosm {
  EvtPancakeToken internal token0;
  EvtPancakeToken internal token1;
  EvtPancakePoolManager public immutable clManagerMock;
  EvtPancakePermit2 public immutable permit2Mock;

  uint256 public nextTokenId = 7;
  uint128 internal liquidity_;
  uint256 internal stagedFee0;
  uint256 internal stagedFee1;
  uint256 internal stagedPrincipal0;
  uint256 internal stagedPrincipal1;
  address internal positionOwner;

  constructor(EvtPancakeToken _token0, EvtPancakeToken _token1) {
    token0 = _token0;
    token1 = _token1;
    clManagerMock = new EvtPancakePoolManager();
    permit2Mock = new EvtPancakePermit2();
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

  function clPoolManager() external view returns (address) {
    return address(clManagerMock);
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

  function getPoolAndPositionInfo(uint256) public view returns (PoolKey memory key, CLPositionInfo info) {
    key.currency0 = Currency.wrap(address(token0));
    key.currency1 = Currency.wrap(address(token1));
    key.hooks = IHooks(address(0));
    key.poolManager = IPoolManager(address(clManagerMock));
    key.fee = 500;
    key.parameters = bytes32(uint256(uint24(60)) << 16);
    info = CLPositionInfoLibrary.initialize(key, -60, 60);
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
contract EvtPancakeConfigManager {
  function platformFeeBasisPoint() external pure returns (uint16) {
    return 0;
  }

  function feeRecipient() external pure returns (address) {
    return address(0xFEE);
  }
}

/// @dev Delegatecall context standing in for SharedVault (minimal ISharedVault surface).
contract EvtPancakeVaultHarness {
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
    SharedPancakeV4StrategyLib.swapAndMintCalldata(address(0xD00D), posm, params);
  }

  function swapAndIncrease(address posm, uint256 tokenId, bytes memory params) external {
    SharedPancakeV4StrategyLib.swapAndIncreaseCalldata(address(0xD00D), posm, tokenId, params);
  }

  function executeInstruction(address posm, uint256 tokenId, ISharedPancakeV4Utils.Instructions memory instructions)
    external
  {
    SharedPancakeV4StrategyLib.executeInstructionBytes(address(0xD00D), posm, tokenId, abi.encode(instructions));
  }
}

contract SharedPancakeV4StrategyEventsTest is Test {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;
  uint256 internal constant TOKEN_ID = 1;

  EvtPancakeToken internal token0;
  EvtPancakeToken internal token1;
  EvtPancakePosm internal posm;
  EvtPancakeVaultHarness internal harness;

  function setUp() public {
    token0 = new EvtPancakeToken("ET0");
    token1 = new EvtPancakeToken("ET1");
    harness = new EvtPancakeVaultHarness(address(new EvtPancakeConfigManager()));
    harness.addVaultToken(address(token0));
    harness.addVaultToken(address(token1));
    posm = new EvtPancakePosm(token0, token1);
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

  function _poolKey() internal view returns (PoolKey memory key) {
    key.currency0 = Currency.wrap(address(token0));
    key.currency1 = Currency.wrap(address(token1));
    key.hooks = IHooks(address(0));
    key.poolManager = IPoolManager(posm.clPoolManager());
    key.fee = 500;
    key.parameters = bytes32(uint256(uint24(60)) << 16);
  }

  function _inputs(uint256 amount0, uint256 amount1)
    internal
    view
    returns (ISharedPancakeV4Utils.InputTokenParams[] memory)
  {
    ISharedPancakeV4Utils.InputTokenParams[] memory inputs = new ISharedPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: amount0 });
    inputs[1] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: amount1 });
    return inputs;
  }

  function test_pancake_swapAndMint_emitsSwapAndMint() public {
    uint256 amount0 = 5e18;
    uint256 amount1 = 5e18;
    ISharedPancakeV4Utils.SwapAndMintParams memory p;
    p.posm = address(posm);
    p.poolKey = _poolKey();
    p.mintParams =
      ISharedPancakeV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.inputTokens = _inputs(amount0, amount1);
    p.sweepTokens = new Currency[](0);

    uint256 expectedTokenId = posm.nextTokenId();
    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedPancakeV4Utils.SwapAndMint(
      address(posm), expectedTokenId, _quotedLiquidity(amount0, amount1), amount0, amount1
    );
    harness.swapAndMint(address(posm), abi.encodeCall(ISharedPancakeV4Utils.swapAndMint, (p)));
  }

  function test_pancake_swapAndIncrease_emitsSwapAndIncrease() public {
    uint256 amount0 = 4e18;
    uint256 amount1 = 6e18;
    ISharedPancakeV4Utils.SwapAndIncreaseParams memory p;
    p.posm = address(posm);
    p.tokenId = TOKEN_ID;
    p.increaseParams = ISharedPancakeV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.inputTokens = _inputs(amount0, amount1);
    p.sweepTokens = new Currency[](0);

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedPancakeV4Utils.SwapAndIncrease(
      address(posm), TOKEN_ID, _quotedLiquidity(amount0, amount1), amount0, amount1
    );
    harness.swapAndIncrease(address(posm), TOKEN_ID, abi.encodeCall(ISharedPancakeV4Utils.swapAndIncrease, (p)));
  }

  /// @dev v4utils parity: CompoundFees reports the position's TOTAL liquidity after the compound
  ///      (the mock's INCREASE is a no-op, so it stays at the staged 5_000) and the net collected
  ///      fee amounts pushed into the increase (zero performance fees configured).
  function test_pancake_compound_emitsCompoundFees() public {
    posm.setLiquidity(5000);
    posm.stageFees(1e18, 2e18);

    ISharedPancakeV4Utils.CompoundFeesParams memory p;
    p.collectFeesHookData = "";
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.increaseParams = ISharedPancakeV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: 0 });

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedPancakeV4Utils.CompoundFees(address(posm), TOKEN_ID, 5000, 1e18, 2e18);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedPancakeV4Utils.Instructions({ action: ISharedPancakeV4Utils.UtilActions.COMPOUND, params: abi.encode(p) })
    );
  }

  /// @dev `liquidity` reports the REQUESTED decrease and `token`/`amount` the swapDestToken with this
  ///      operation's proceeds in it (principal token1 here; no swaps, no fees staged).
  function test_pancake_decreaseAndSwap_emitsDecreaseAndSwap() public {
    posm.setLiquidity(1_000_000);
    posm.stagePrincipal(3e18, 4e18);

    ISharedPancakeV4Utils.DecreaseAndSwapParams memory p;
    p.decreaseParams = ISharedPancakeV4Utils.DecreaseLiquidityParams({
      liquidity: 600_000, deadline: 0, amount0Min: 0, amount1Min: 0, hookData: ""
    });
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.swapDestToken = Currency.wrap(address(token1));

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedPancakeV4Utils.DecreaseAndSwap(address(posm), TOKEN_ID, 600_000, Currency.wrap(address(token1)), 4e18);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedPancakeV4Utils.Instructions({
        action: ISharedPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(p)
      })
    );
  }

  /// @dev A swapDestToken that is not a pool token cannot be measured: `amount` reports 0 (and the
  ///      action itself must not revert — the field is event-labeling only).
  function test_pancake_decreaseAndSwap_nonPoolDestToken_reportsZeroAmount() public {
    posm.setLiquidity(1_000_000);
    posm.stagePrincipal(3e18, 4e18);

    ISharedPancakeV4Utils.DecreaseAndSwapParams memory p;
    p.decreaseParams = ISharedPancakeV4Utils.DecreaseLiquidityParams({
      liquidity: 600_000, deadline: 0, amount0Min: 0, amount1Min: 0, hookData: ""
    });
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.swapDestToken = Currency.wrap(address(0xDEAD));

    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedPancakeV4Utils.DecreaseAndSwap(address(posm), TOKEN_ID, 600_000, Currency.wrap(address(0xDEAD)), 0);
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedPancakeV4Utils.Instructions({
        action: ISharedPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(p)
      })
    );
  }

  function test_pancake_adjustRange_emitsAdjustRange() public {
    posm.setLiquidity(1_000_000);
    posm.stagePrincipal(3e18, 4e18);

    ISharedPancakeV4Utils.AdjustRangeParams memory p;
    p.collectFeesHookData = "";
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.mintParams =
      ISharedPancakeV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });

    uint256 expectedNewTokenId = posm.nextTokenId();
    vm.expectEmit(true, true, true, true, address(harness));
    emit ISharedPancakeV4Utils.AdjustRange(
      address(posm), TOKEN_ID, expectedNewTokenId, _quotedLiquidity(3e18, 4e18), 3e18, 4e18
    );
    harness.executeInstruction(
      address(posm),
      TOKEN_ID,
      ISharedPancakeV4Utils.Instructions({
        action: ISharedPancakeV4Utils.UtilActions.ADJUST_RANGE, params: abi.encode(p)
      })
    );
  }
}
