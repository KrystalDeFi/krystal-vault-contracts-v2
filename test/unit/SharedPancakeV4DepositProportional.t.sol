// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";

import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { PoolId } from "infinity-core/src/types/PoolId.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { IHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";

// ---------------------------------------------------------------------------
// SharedPancakeV4StrategyLib.depositProportional slippage-floor coverage —
// twin of SharedV4DepositProportional.t.sol (the libs are forks and must stay
// mirrored). Same four pins: floor reverts on under-consumption, bps == 0
// disarms it, full consumption passes, zero amounts short-circuit before the
// posm whitelist guard.
// ---------------------------------------------------------------------------

contract DepPropPancakeToken {
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

  /// @dev Test-only hook so the POSM mock can model consumption without the Permit2 plumbing.
  function devMove(address from, address to, uint256 amount) external {
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
  }
}

contract DepPropPancakePermit2 {
  function approve(address, address, uint160, uint48) external { }
}

/// @dev CL pool manager at a fixed 1:1 price; the Pancake lib calls getSlot0 DIRECTLY (no extsload).
contract DepPropPancakePoolManager {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  function getSlot0(PoolId) external pure returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
    return (SQRT_PRICE_1_1, 0, 0, 0);
  }
}

/// @dev CL POSM whose INCREASE consumption is switchable: `consume = false` models the misbehaving
///      manager the slippage floor exists to catch.
contract DepPropPancakePosm {
  DepPropPancakeToken internal token0;
  DepPropPancakeToken internal token1;
  DepPropPancakePoolManager public immutable clManagerMock;
  DepPropPancakePermit2 public immutable permit2Mock;
  bool public consume;

  constructor(DepPropPancakeToken _token0, DepPropPancakeToken _token1) {
    token0 = _token0;
    token1 = _token1;
    clManagerMock = new DepPropPancakePoolManager();
    permit2Mock = new DepPropPancakePermit2();
  }

  function setConsume(bool _consume) external {
    consume = _consume;
  }

  function clPoolManager() external view returns (address) {
    return address(clManagerMock);
  }

  function permit2() external view returns (address) {
    return address(permit2Mock);
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory key, CLPositionInfo info) {
    key.currency0 = Currency.wrap(address(token0));
    key.currency1 = Currency.wrap(address(token1));
    key.hooks = IHooks(address(0));
    key.poolManager = IPoolManager(address(clManagerMock));
    key.fee = 500;
    key.parameters = bytes32(uint256(uint24(60)) << 16);
    info = CLPositionInfoLibrary.initialize(key, -60, 60);
  }

  function modifyLiquidities(bytes calldata data, uint256) external payable {
    if (!consume) return; // misbehaving manager: takes nothing
    (, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));
    // INCREASE param layout: (tokenId, liquidity, amount0Max, amount1Max, hookData)
    (,, uint128 amount0, uint128 amount1,) = abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
    if (amount0 > 0) token0.devMove(msg.sender, address(this), amount0);
    if (amount1 > 0) token1.devMove(msg.sender, address(this), amount1);
  }
}

contract DepPropPancakeConfigManager {
  mapping(address => bool) public isWhitelistedNfpm;

  function setNfpm(address nfpm, bool ok) external {
    isWhitelistedNfpm[nfpm] = ok;
  }
}

/// @dev Delegatecall context standing in for SharedVault (minimal ISharedVault surface).
contract DepPropPancakeVaultHarness {
  address public configManager;
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

  function depositProportional(address strategy, address posm, uint256 tokenId, uint256 a0, uint256 a1, uint16 bps)
    external
  {
    (bool ok, bytes memory err) =
      strategy.delegatecall(abi.encodeCall(ISharedStrategy.depositProportional, (posm, tokenId, a0, a1, bps)));
    if (!ok) {
      assembly {
        revert(add(err, 32), mload(err))
      }
    }
  }
}

contract SharedPancakeV4DepositProportionalTest is Test {
  uint256 internal constant TOKEN_ID = 1;

  DepPropPancakeToken internal token0;
  DepPropPancakeToken internal token1;
  DepPropPancakePosm internal posm;
  DepPropPancakeConfigManager internal cm;
  DepPropPancakeVaultHarness internal vault;
  SharedPancakeV4Strategy internal strategy;

  function setUp() public {
    token0 = new DepPropPancakeToken("DPT0");
    token1 = new DepPropPancakeToken("DPT1");
    posm = new DepPropPancakePosm(token0, token1);
    cm = new DepPropPancakeConfigManager();
    cm.setNfpm(address(posm), true);

    vault = new DepPropPancakeVaultHarness(address(cm));
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));
    token0.mint(address(vault), 100e18);
    token1.mint(address(vault), 100e18);

    strategy = new SharedPancakeV4Strategy(address(0xD00D)); // router unused on this path
  }

  /// @dev Twin of the V4 test: zero consumption against a 1% floor must revert InsufficientOutput.
  function test_pancake_depositProportional_revertsWhenConsumedBelowSlippageFloor() public {
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 1e18, 1e18, 100);
  }

  /// @dev Twin of the V4 test: slippageBps == 0 disarms the floor.
  function test_pancake_depositProportional_zeroSlippageBpsDisablesFloor() public {
    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 1e18, 1e18, 0);

    assertEq(token0.balanceOf(address(vault)), 100e18, "nothing consumed, nothing lost");
    assertEq(token1.balanceOf(address(vault)), 100e18, "nothing consumed, nothing lost");
  }

  /// @dev Twin of the V4 test: full consumption of the encoded amounts satisfies the floor.
  function test_pancake_depositProportional_passesWhenConsumptionMeetsFloor() public {
    posm.setConsume(true);

    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 1e18, 1e18, 100);

    assertLt(token0.balanceOf(address(vault)), 100e18, "token0 consumed by the increase");
    assertLt(token1.balanceOf(address(vault)), 100e18, "token1 consumed by the increase");
    assertGt(token0.balanceOf(address(posm)), 0, "POSM received token0");
    assertGt(token1.balanceOf(address(posm)), 0, "POSM received token1");
  }

  /// @dev Twin of the V4 test: (0, 0) short-circuits before even the posm whitelist guard.
  function test_pancake_depositProportional_zeroAmountsReturnsBeforeWhitelistCheck() public {
    cm.setNfpm(address(posm), false); // would revert InvalidNfpm if the guard ran

    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 0, 0, 100);

    assertEq(token0.balanceOf(address(vault)), 100e18, "no-op");
    assertEq(token1.balanceOf(address(vault)), 100e18, "no-op");
  }
}
