// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

// ---------------------------------------------------------------------------
// SharedV4StrategyLib.depositProportional slippage-floor coverage.
//
// The floor (`used >= expected * (1 - slippageBps)`, expected quoted from
// getAmountsForLiquidity at the current price) exists to catch a misbehaving /
// non-canonical position manager that consumes less than the quoted amounts.
// Until now only the happy path was exercised (mock POSMs consume nothing and
// every caller passed slippageBps == 0, so the floor never armed). These tests
// pin: (1) the floor REVERTS when consumption falls short, (2) slippageBps == 0
// genuinely disables it, (3) full consumption passes it, and (4) the zero-amount
// early return short-circuits before ANY posm interaction.
// Twin: SharedPancakeV4DepositProportional.t.sol (the libs are forks).
// ---------------------------------------------------------------------------

contract DepPropV4Token {
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

contract DepPropV4Permit2 {
  function approve(address, address, uint160, uint48) external { }
}

/// @dev Pool manager at a fixed 1:1 price, read by the lib via StateLibrary's extsload getSlot0.
contract DepPropV4PoolManager {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  function extsload(bytes32) external pure returns (bytes32) {
    return bytes32(uint256(SQRT_PRICE_1_1));
  }

  function extsload(bytes32, uint256 nSlots) external pure returns (bytes32[] memory values) {
    values = new bytes32[](nSlots);
  }
}

/// @dev POSM whose INCREASE_LIQUIDITY consumption is switchable: `consume = false` models the
///      misbehaving manager the slippage floor exists to catch; `consume = true` pulls exactly the
///      amounts the lib encoded into the increase action.
contract DepPropV4Posm {
  DepPropV4Token internal token0;
  DepPropV4Token internal token1;
  DepPropV4PoolManager public immutable poolManagerMock;
  DepPropV4Permit2 public immutable permit2Mock;
  bool public consume;

  constructor(DepPropV4Token _token0, DepPropV4Token _token1) {
    token0 = _token0;
    token1 = _token1;
    poolManagerMock = new DepPropV4PoolManager();
    permit2Mock = new DepPropV4Permit2();
  }

  function setConsume(bool _consume) external {
    consume = _consume;
  }

  function poolManager() external view returns (address) {
    return address(poolManagerMock);
  }

  function permit2() external view returns (address) {
    return address(permit2Mock);
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory key, PositionInfo info) {
    key.currency0 = Currency.wrap(address(token0));
    key.currency1 = Currency.wrap(address(token1));
    key.fee = 500;
    key.tickSpacing = 60;
    key.hooks = IHooks(address(0));
    info = PositionInfoLibrary.initialize(key, -60, 60);
  }

  function modifyLiquidities(bytes calldata data, uint256) external payable {
    if (!consume) return; // misbehaving manager: takes nothing
    (, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));
    // INCREASE_LIQUIDITY param layout: (tokenId, liquidity, amount0Max, amount1Max, hookData)
    (,, uint128 amount0, uint128 amount1,) = abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
    if (amount0 > 0) token0.devMove(msg.sender, address(this), amount0);
    if (amount1 > 0) token1.devMove(msg.sender, address(this), amount1);
  }
}

contract DepPropV4ConfigManager {
  mapping(address => bool) public isWhitelistedNfpm;

  function setNfpm(address nfpm, bool ok) external {
    isWhitelistedNfpm[nfpm] = ok;
  }
}

/// @dev Delegatecall context standing in for SharedVault: holds the tokens and implements the
///      minimal ISharedVault surface depositProportional consults (configManager, isVaultToken, weth).
contract DepPropV4VaultHarness {
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

contract SharedV4DepositProportionalTest is Test {
  uint256 internal constant TOKEN_ID = 1;

  DepPropV4Token internal token0;
  DepPropV4Token internal token1;
  DepPropV4Posm internal posm;
  DepPropV4ConfigManager internal cm;
  DepPropV4VaultHarness internal vault;
  SharedV4Strategy internal strategy;

  function setUp() public {
    token0 = new DepPropV4Token("DT0");
    token1 = new DepPropV4Token("DT1");
    posm = new DepPropV4Posm(token0, token1);
    cm = new DepPropV4ConfigManager();
    cm.setNfpm(address(posm), true);

    vault = new DepPropV4VaultHarness(address(cm));
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));
    token0.mint(address(vault), 100e18);
    token1.mint(address(vault), 100e18);

    strategy = new SharedV4Strategy(address(0xD00D)); // router unused on this path
  }

  /// @dev A POSM that consumes NOTHING while the caller demanded a 1% floor must revert: the quoted
  ///      in-range amounts at the 1:1 price are ~1e18 per side, and used0 == used1 == 0.
  function test_depositProportional_revertsWhenConsumedBelowSlippageFloor() public {
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 1e18, 1e18, 100);
  }

  /// @dev slippageBps == 0 genuinely disarms the floor: the same zero-consumption POSM passes and the
  ///      vault keeps its tokens (the production default for SharedVault deposit top-ups with bps = 0).
  function test_depositProportional_zeroSlippageBpsDisablesFloor() public {
    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 1e18, 1e18, 0);

    assertEq(token0.balanceOf(address(vault)), 100e18, "nothing consumed, nothing lost");
    assertEq(token1.balanceOf(address(vault)), 100e18, "nothing consumed, nothing lost");
  }

  /// @dev Full consumption of the encoded amounts satisfies the floor (used == requested >= expected).
  function test_depositProportional_passesWhenConsumptionMeetsFloor() public {
    posm.setConsume(true);

    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 1e18, 1e18, 100);

    assertLt(token0.balanceOf(address(vault)), 100e18, "token0 consumed by the increase");
    assertLt(token1.balanceOf(address(vault)), 100e18, "token1 consumed by the increase");
    assertGt(token0.balanceOf(address(posm)), 0, "POSM received token0");
    assertGt(token1.balanceOf(address(posm)), 0, "POSM received token1");
  }

  /// @dev (0, 0) must return before ANY posm interaction — even the whitelist check. Pins the
  ///      early-return ordering: a de-whitelisted posm with zero amounts is a silent no-op, matching
  ///      SharedVault's behavior of skipping empty LP top-ups.
  function test_depositProportional_zeroAmountsReturnsBeforeWhitelistCheck() public {
    cm.setNfpm(address(posm), false); // would revert InvalidNfpm if the guard ran

    vault.depositProportional(address(strategy), address(posm), TOKEN_ID, 0, 0, 100);

    assertEq(token0.balanceOf(address(vault)), 100e18, "no-op");
    assertEq(token1.balanceOf(address(vault)), 100e18, "no-op");
  }
}
