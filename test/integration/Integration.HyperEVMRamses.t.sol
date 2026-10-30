// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { RamsesFarmingStrategy } from "../../contracts/private-vault/strategies/farm/RamsesFarmingStrategy.sol";
import { AerodromeFarmingStrategy } from "../../contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol";
import { PancakeV3FarmingStrategy } from "../../contracts/private-vault/strategies/farm/PancakeV3FarmingStrategy.sol";
import { V3UtilsStrategy } from "../../contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import {
  IRamsesV3PositionManager
} from "../../contracts/common/interfaces/protocols/ramses/IRamsesV3PositionManager.sol";
import { IRamsesV3Pool } from "../../contracts/common/interfaces/protocols/ramses/IRamsesV3Pool.sol";
import { IRamsesGaugeV3 } from "../../contracts/common/interfaces/protocols/ramses/IRamsesGaugeV3.sol";

/// @notice Fork base for the Ramses suites against Ramses on HyperEVM (non-hermetic like the other
///         Integration.HyperEVM* suites: excluded from the offline fork gate). WHYPE/USDC is a gauged pool whose swap
///         fees all go to voters (feeProtocol 100%), so its LPs earn RAM only.
abstract contract HyperEVMRamsesFork is TestCommon {
  uint256 internal constant FORK_BLOCK = 49_899_000;
  uint256 internal constant Q64 = 0x10000000000000000;

  address internal constant VOTER = 0x9aab8C415aF5936b09C595B09B1ff15cbaDCD843;
  address internal constant RAMSES_NFPM = 0xB3F77C5134D643483253D22E0Ca24627aE42ED51;
  address internal constant RAMSES_GAUGE_FACTORY = 0xE17988013E15d29B655634Da0056ba27BA4D3E27;
  address internal constant RAM = 0x555570a286F15EbDFE42B66eDE2f724Aa1AB5555;
  address internal constant WHYPE = 0x5555555555555555555555555555555555555555;
  address internal constant HYPER_USDC = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
  address internal constant WHYPE_USDC_POOL = 0x5a177cF0EfFB7e0e7115D792E587c1A5a9CbC9D4;
  address internal constant WHYPE_USDC_GAUGE = 0x1d21655d65f8ab051eC16010c8F548f0D5C446BC;
  /// @dev Krystal V3Utils on HyperEVM; whitelists the Ramses position manager and decodes it as `RAMSES_V3`.
  address internal constant V3_UTILS = 0xb4acbC082b5e7dEd571c98EE4257778a9D784B36;
  uint8 internal constant PROTOCOL_RAMSES_V3 = 2;
  int24 internal constant TICK_SPACING = 5;

  address internal constant OWNER = address(0xA11CE);
  address internal constant OPERATOR = address(0x0FE7A70);

  address internal feeRecipient = makeAddr("feeRecipient");
  address internal swapRouter = makeAddr("swapRouter");
  IRamsesGaugeV3 internal gauge = IRamsesGaugeV3(WHYPE_USDC_GAUGE);
  int24 internal tickLower;
  int24 internal tickUpper;

  function setUp() public virtual {
    vm.createSelectFork(vm.envString("HYPEREVM_RPC_URL"), FORK_BLOCK);
    (, int24 tick,,,,,) = IRamsesV3Pool(WHYPE_USDC_POOL).slot0();
    tickLower = (tick / TICK_SPACING - 100) * TICK_SPACING;
    tickUpper = (tick / TICK_SPACING + 100) * TICK_SPACING;
  }

  /// A WHYPE/USDC position minted straight on the Ramses position manager for `owner`.
  function _mintAs(address owner) internal returns (uint256 tokenId) {
    _fundAndApprove(owner);
    vm.prank(owner);
    (tokenId,,,) = IRamsesV3PositionManager(RAMSES_NFPM)
      .mint(
        IRamsesV3PositionManager.MintParams({
        token0: WHYPE,
        token1: HYPER_USDC,
        tickSpacing: TICK_SPACING,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: 10 ether,
        amount1Desired: 2000e6,
        amount0Min: 0,
        amount1Min: 0,
        recipient: owner,
        deadline: block.timestamp
      })
      );
  }

  /// `owner` holds what `_mintAs` deposits, approved to the Ramses position manager.
  function _fundAndApprove(address owner) internal {
    setErc20Balance(WHYPE, owner, 10 ether);
    setErc20Balance(HYPER_USDC, owner, 2000e6);
    vm.startPrank(owner);
    IERC20(WHYPE).approve(RAMSES_NFPM, type(uint256).max);
    IERC20(HYPER_USDC).approve(RAMSES_NFPM, type(uint256).max);
    vm.stopPrank();
  }

  function _privateVault() internal returns (PrivateVault vault, PrivateConfigManager configManager) {
    configManager = new PrivateConfigManager();
    address[] memory callers = new address[](1);
    callers[0] = OPERATOR;
    configManager.initialize(address(this), new address[](0), callers, feeRecipient);
    vault = new PrivateVault();
    vault.initialize(OWNER, address(configManager), "ramses");
  }

  function _whitelistPrivateTarget(PrivateConfigManager configManager, address target) internal {
    address[] memory targets = new address[](1);
    targets[0] = target;
    configManager.setWhitelistTargets(targets, true);
  }

  /// The operator delegatecalls `strategy` from `vault`.
  function _privateCall(PrivateVault vault, address strategy, bytes memory data) internal {
    address[] memory targets = new address[](1);
    targets[0] = strategy;
    bytes[] memory calls = new bytes[](1);
    calls[0] = data;
    _privateMulticall(vault, targets, calls);
  }

  /// The operator delegatecalls each of `targets` from `vault`, in one transaction.
  function _privateMulticall(PrivateVault vault, address[] memory targets, bytes[] memory calls) internal {
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](targets.length);
    for (uint256 i; i < targets.length; i++) {
      callTypes[i] = IPrivateCommon.CallType.DELEGATECALL;
    }
    vm.prank(OPERATOR);
    vault.multicall(targets, new uint256[](targets.length), calls, callTypes);
  }
}

/// @notice RamsesFarmingStrategy against the live Ramses deployment.
contract HyperEVMRamsesIntegrationTest is HyperEVMRamsesFork {
  function test_private_harvestClaimsTheRamAVaultPositionEarned() public {
    (PrivateVault vault, PrivateConfigManager configManager) = _privateVault();
    RamsesFarmingStrategy strategy = new RamsesFarmingStrategy(VOTER, address(configManager));
    _whitelistPrivateTarget(configManager, address(strategy));

    uint256 tokenId = _mintAs(address(vault));
    vm.warp(vm.getBlockTimestamp() + 1 days);
    uint256 earned = gauge.earned(RAM, tokenId);
    assertGt(earned, 0, "an in-range position earns RAM");

    uint64 rewardFeeX64 = uint64(Q64 * 5 / 100);
    uint64 gasFeeX64 = uint64(Q64 / 100);
    _privateCall(
      vault, address(strategy), abi.encodeCall(RamsesFarmingStrategy.harvest, (tokenId, rewardFeeX64, gasFeeX64, true))
    );

    uint256 fee = Math.mulDiv(earned, rewardFeeX64, Q64) + Math.mulDiv(earned, gasFeeX64, Q64);
    assertEq(IERC20(RAM).balanceOf(feeRecipient), fee);
    assertEq(IERC20(RAM).balanceOf(OWNER), earned - fee);
    assertEq(gauge.earned(RAM, tokenId), 0);
    assertEq(IERC721(RAMSES_NFPM).ownerOf(tokenId), address(vault));
  }

  /// The safe way to run a V3Utils operation on a Ramses position: harvest first, in the same multicall. The vault
  /// gets all the RAM and V3Utils, which holds the NFT during the operation, gets none.
  function test_private_harvestFirst_thenV3UtilsExit_leaksNoRamToV3Utils() public {
    (PrivateVault vault, PrivateConfigManager configManager) = _privateVault();
    RamsesFarmingStrategy ramsesStrategy = new RamsesFarmingStrategy(VOTER, address(configManager));
    V3UtilsStrategy v3UtilsStrategy = new V3UtilsStrategy(V3_UTILS);
    _whitelistPrivateTarget(configManager, address(ramsesStrategy));
    _whitelistPrivateTarget(configManager, address(v3UtilsStrategy));
    uint256 tokenId = _mintAs(address(vault));
    vm.warp(vm.getBlockTimestamp() + 1 days);
    uint256 earned = gauge.earned(RAM, tokenId);
    assertGt(earned, 0);
    uint256 v3UtilsRamBefore = IERC20(RAM).balanceOf(V3_UTILS);

    (,,,,, uint128 liquidity,,,,) = IRamsesV3PositionManager(RAMSES_NFPM).positions(tokenId);
    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.protocol = PROTOCOL_RAMSES_V3;
    instructions.liquidity = liquidity;
    instructions.deadline = block.timestamp;
    address[] memory targets = new address[](2);
    targets[0] = address(ramsesStrategy);
    targets[1] = address(v3UtilsStrategy);
    bytes[] memory calls = new bytes[](2);
    calls[0] = abi.encodeCall(RamsesFarmingStrategy.harvest, (tokenId, 0, 0, false));
    calls[1] =
      abi.encodeCall(V3UtilsStrategy.safeTransferNft, (RAMSES_NFPM, tokenId, instructions, new address[](0), false));
    _privateMulticall(vault, targets, calls);

    assertEq(IERC20(RAM).balanceOf(address(vault)), earned, "the vault got all the RAM");
    assertEq(IERC20(RAM).balanceOf(V3_UTILS), v3UtilsRamBefore, "V3Utils got none");
    assertEq(IERC721(RAMSES_NFPM).ownerOf(tokenId), address(vault));
  }
}

/// @notice Proof, against the live Ramses deployment, that the other strategies can't farm on Ramses, and that the
///         shared-vault ones can't even provide liquidity there, so shared vaults stay off Ramses. Each test also pins
///         the root cause on Ramses' contracts directly, so a failure here means Ramses changed, not the strategy.
contract HyperEVMRamsesIncompatibilityTest is HyperEVMRamsesFork {
  bytes4 internal constant UNISWAP_V3_MINT =
    bytes4(keccak256("mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))"));
  bytes4 internal constant SLIPSTREAM_MINT = bytes4(
    keccak256("mint((address,address,int24,int24,int24,uint256,uint256,uint256,uint256,address,uint256,uint160))")
  );

  /// `target` has no `signature` getter (a call with no arguments can only fail if it's missing or reverts).
  function _assertMissing(address target, string memory signature) internal {
    (bool ok,) = target.call(abi.encodeWithSignature(signature));
    assertFalse(ok, signature);
  }

  /// How many words Ramses' `positions` returns: 10, where Uniswap V3 and Slipstream return (and decode) 12.
  function _positionWords(uint256 tokenId) internal view returns (uint256) {
    (bool ok, bytes memory data) = RAMSES_NFPM.staticcall(abi.encodeWithSignature("positions(uint256)", tokenId));
    require(ok, "positions");
    return data.length / 32;
  }

  function _poolFee() internal view returns (uint24) {
    (bool ok, bytes memory data) = WHYPE_USDC_POOL.staticcall(abi.encodeWithSignature("fee()"));
    require(ok, "fee");
    return abi.decode(data, (uint24));
  }

  /// Ramses' position manager rejects `foreignMint` — the position `_mintAs` opens, encoded for another protocol's
  /// `mint` — and takes the same position in its own encoding.
  function _assertRejectsForeignMint(bytes memory foreignMint, string memory what) internal {
    _fundAndApprove(address(this));
    (bool ok,) = RAMSES_NFPM.call(foreignMint);
    assertFalse(ok, what);
    _mintAs(address(this));
  }

  /// Uniswap V3's `mint` is keyed by fee (the pool's real one here).
  function _uniswapV3Mint() internal view returns (bytes memory) {
    return abi.encodeWithSelector(
      UNISWAP_V3_MINT,
      WHYPE,
      HYPER_USDC,
      _poolFee(),
      tickLower,
      tickUpper,
      10 ether,
      2000e6,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  /// Slipstream's `mint` adds a sqrtPriceX96, 0 for a pool that exists.
  function _slipstreamMint() internal view returns (bytes memory) {
    return abi.encodeWithSelector(
      SLIPSTREAM_MINT,
      WHYPE,
      HYPER_USDC,
      TICK_SPACING,
      tickLower,
      tickUpper,
      10 ether,
      2000e6,
      0,
      0,
      address(this),
      block.timestamp,
      uint160(0)
    );
  }

  /// A WHYPE/USDC shared vault whose config whitelists `strategies` and the Ramses position manager.
  function _sharedVault(address[] memory strategies) internal returns (SharedVault vault) {
    SharedConfigManager configManager = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = RAMSES_NFPM;
    address[] memory routers = new address[](1);
    routers[0] = swapRouter;
    configManager.initialize(
      address(this), strategies, new address[](0), feeRecipient, 1000, nfpms, routers, new address[](0)
    );

    vault = new SharedVault();
    setErc20Balance(WHYPE, address(vault), 20 ether);
    setErc20Balance(HYPER_USDC, address(vault), 4000e6);
    vm.prank(OWNER);
    vault.initialize(
      "Ramses WHYPE/USDC",
      [WHYPE, HYPER_USDC, address(0), address(0)],
      [uint256(20 ether), uint256(4000e6), 0, 0],
      OWNER,
      OWNER,
      address(configManager),
      WHYPE,
      500
    );
  }

  function _execute(SharedVault vault, address strategy, bytes memory data) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({ target: strategy, data: data, callType: ISharedCommon.CallType.DELEGATECALL });
    vm.prank(OWNER);
    vault.execute(actions);
  }

  /// SWAP_AND_MINT (op 0 in every shared strategy) of 10 WHYPE + 2000 USDC on the Ramses position manager.
  function _mintData(uint24 fee, int24 tickSpacing) internal view returns (bytes memory) {
    IV3Utils.SwapAndMintParams memory params;
    params.nfpm = RAMSES_NFPM;
    params.token0 = WHYPE;
    params.token1 = HYPER_USDC;
    params.fee = fee;
    params.tickSpacing = tickSpacing;
    params.tickLower = tickLower;
    params.tickUpper = tickUpper;
    params.amount0 = 10 ether;
    params.amount1 = 2000e6;
    params.deadline = block.timestamp;
    return bytes.concat(abi.encode(uint256(0)), abi.encode(params, new address[](0), new uint256[](0), uint256(0)));
  }

  /// Ramses' gauged pools send every swap fee to voters: providing liquidity there earns RAM or nothing.
  function test_ramses_gaugedPoolLpsEarnNoSwapFees() public view {
    (,,,,, uint24 feeProtocol,) = IRamsesV3Pool(WHYPE_USDC_POOL).slot0();
    assertEq(feeProtocol, 1_000_000, "100% of swap fees to voters");
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Private vault
  // ---------------------------------------------------------------------------------------------------------------

  /// AerodromeFarmingStrategy can't even be deployed for Ramses: its constructor reads the position manager from the
  /// gauge factory's `nft()`, which neither Ramses' CL gauge factory nor its Voter has.
  function test_private_aerodromeFarmingStrategy_cannotBeDeployedForRamses() public {
    (, PrivateConfigManager configManager) = _privateVault();
    _assertMissing(RAMSES_GAUGE_FACTORY, "nft()");
    _assertMissing(VOTER, "nft()");

    vm.expectRevert();
    new AerodromeFarmingStrategy(RAMSES_GAUGE_FACTORY, address(configManager));
    vm.expectRevert();
    new AerodromeFarmingStrategy(VOTER, address(configManager));
  }

  /// Nor would it work deployed: its stake and harvest paths locate the gauge through the position manager's
  /// `factory()` and the pool's `gauge()` (neither exists on Ramses) after decoding `positions` as Slipstream's 12
  /// fields (Ramses returns 10), then read the gauge's `rewardToken()` (missing) or stake into it, and Ramses'
  /// gauges are non-custodial: `deposit` fails even with the NFT approved to the gauge.
  function test_private_aerodromeFarmingCalls_missOnRamses() public {
    uint256 tokenId = _mintAs(address(this));
    _assertMissing(RAMSES_NFPM, "factory()");
    assertEq(_positionWords(tokenId), 10);
    _assertMissing(WHYPE_USDC_POOL, "gauge()");
    _assertMissing(WHYPE_USDC_GAUGE, "rewardToken()");

    IERC721(RAMSES_NFPM).approve(WHYPE_USDC_GAUGE, tokenId);
    (bool ok,) = WHYPE_USDC_GAUGE.call(abi.encodeWithSignature("deposit(uint256)", tokenId));
    assertFalse(ok, "the gauge takes no deposit");
    assertEq(IERC721(RAMSES_NFPM).ownerOf(tokenId), address(this));
  }

  /// PancakeV3FarmingStrategy needs a MasterChef to take the NFT and pay CAKE; Ramses has none. Pointed at the gauge,
  /// both its stake and its harvest revert (the gauge has neither `nonfungiblePositionManager()` nor `CAKE()`), and the
  /// RAM the position earned stays unclaimed.
  function test_private_pancakeV3FarmingStrategy_cannotStakeOrHarvestOnRamses() public {
    (PrivateVault vault, PrivateConfigManager configManager) = _privateVault();
    PancakeV3FarmingStrategy strategy = new PancakeV3FarmingStrategy(WHYPE_USDC_GAUGE, address(configManager));
    _whitelistPrivateTarget(configManager, address(strategy));
    uint256 tokenId = _mintAs(address(vault));
    vm.warp(vm.getBlockTimestamp() + 1 days);
    uint256 earned = gauge.earned(RAM, tokenId);
    assertGt(earned, 0);
    _assertMissing(WHYPE_USDC_GAUGE, "nonfungiblePositionManager()");
    _assertMissing(WHYPE_USDC_GAUGE, "CAKE()");

    vm.expectRevert(IPrivateVault.StrategyDelegateCallFailed.selector);
    _privateCall(vault, address(strategy), abi.encodeCall(PancakeV3FarmingStrategy.deposit, (tokenId)));
    vm.expectRevert(IPrivateVault.StrategyDelegateCallFailed.selector);
    _privateCall(vault, address(strategy), abi.encodeCall(PancakeV3FarmingStrategy.harvest, (tokenId, 0, 0, false)));

    assertEq(IERC20(RAM).balanceOf(address(vault)), 0);
    assertEq(gauge.earned(RAM, tokenId), earned, "still unclaimed");
  }

  /// V3UtilsStrategy can't add liquidity to a Ramses position: Ramses only lets the owner or an approved address
  /// increase it, and V3Utils (which calls `increaseLiquidity` for the vault) is neither.
  function test_private_v3UtilsStrategy_swapAndIncreaseLiquidity_revertsOnRamses() public {
    (PrivateVault vault, PrivateConfigManager configManager) = _privateVault();
    V3UtilsStrategy strategy = new V3UtilsStrategy(V3_UTILS);
    _whitelistPrivateTarget(configManager, address(strategy));
    uint256 tokenId = _mintAs(address(vault));
    setErc20Balance(WHYPE, address(vault), 1 ether);
    setErc20Balance(HYPER_USDC, address(vault), 200e6);

    IV3Utils.SwapAndIncreaseLiquidityParams memory params;
    params.protocol = PROTOCOL_RAMSES_V3;
    params.nfpm = RAMSES_NFPM;
    params.tokenId = tokenId;
    params.amount0 = 1 ether;
    params.amount1 = 200e6;
    params.deadline = block.timestamp;
    address[] memory tokens = new address[](2);
    tokens[0] = WHYPE;
    tokens[1] = HYPER_USDC;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 1 ether;
    amounts[1] = 200e6;
    bytes memory data = abi.encodeCall(V3UtilsStrategy.swapAndIncreaseLiquidity, (params, 0, tokens, amounts, false));

    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, V3_UTILS, tokenId));
    _privateCall(vault, address(strategy), data);
  }

  /// V3Utils holds the NFT while it works on it, so the RAM Ramses pays out on a liquidity change goes to V3Utils,
  /// not the vault: an exit through V3UtilsStrategy leaks every RAM the position earned since its last claim.
  function test_private_v3UtilsStrategy_exitLeaksTheVaultsRamToV3Utils() public {
    (PrivateVault vault, PrivateConfigManager configManager) = _privateVault();
    V3UtilsStrategy strategy = new V3UtilsStrategy(V3_UTILS);
    _whitelistPrivateTarget(configManager, address(strategy));
    uint256 tokenId = _mintAs(address(vault));
    vm.warp(vm.getBlockTimestamp() + 1 days);
    uint256 earned = gauge.earned(RAM, tokenId);
    assertGt(earned, 0);
    uint256 v3UtilsRamBefore = IERC20(RAM).balanceOf(V3_UTILS);

    (,,,,, uint128 liquidity,,,,) = IRamsesV3PositionManager(RAMSES_NFPM).positions(tokenId);
    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.protocol = PROTOCOL_RAMSES_V3;
    instructions.liquidity = liquidity;
    instructions.deadline = block.timestamp;
    _privateCall(
      vault,
      address(strategy),
      abi.encodeCall(V3UtilsStrategy.safeTransferNft, (RAMSES_NFPM, tokenId, instructions, new address[](0), false))
    );

    assertEq(IERC721(RAMSES_NFPM).ownerOf(tokenId), address(vault), "the NFT came back");
    assertGt(IERC20(WHYPE).balanceOf(address(vault)), 0, "the principal came back");
    assertEq(IERC20(RAM).balanceOf(V3_UTILS) - v3UtilsRamBefore, earned, "the position's RAM went to V3Utils");
    assertEq(IERC20(RAM).balanceOf(address(vault)), 0, "and none of it to the vault");
    assertEq(gauge.earned(RAM, tokenId), 0);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Shared vault
  // ---------------------------------------------------------------------------------------------------------------

  /// SharedV3Strategy can't open a Ramses position: it mints through Uniswap V3's fee-keyed `mint`, which Ramses'
  /// position manager rejects.
  function test_shared_v3Strategy_cannotMintOnRamses() public {
    SharedV3Strategy v3Strategy = new SharedV3Strategy(swapRouter);
    address[] memory strategies = new address[](1);
    strategies[0] = address(v3Strategy);
    SharedVault vault = _sharedVault(strategies);
    _assertRejectsForeignMint(_uniswapV3Mint(), "Uniswap V3's mint");

    bytes memory data = _mintData(_poolFee(), 0);
    vm.expectRevert(ISharedCommon.StrategyCallFailed.selector);
    _execute(vault, address(v3Strategy), data);
  }

  /// SharedAerodromeStrategy can't either: Ramses' position manager rejects Slipstream's `mint` too.
  function test_shared_aerodromeStrategy_cannotMintOnRamses() public {
    SharedAerodromeStrategy aeroStrategy = new SharedAerodromeStrategy(swapRouter);
    address[] memory strategies = new address[](1);
    strategies[0] = address(aeroStrategy);
    SharedVault vault = _sharedVault(strategies);
    _assertRejectsForeignMint(_slipstreamMint(), "Slipstream's mint");

    bytes memory data = _mintData(0, TICK_SPACING);
    vm.expectRevert(ISharedCommon.StrategyCallFailed.selector);
    _execute(vault, address(aeroStrategy), data);
  }

  /// Nor can either take over a Ramses position someone else opened: a vault tracks an NFT only through a strategy
  /// that reads its tokens, and both decode Ramses' 10-field `positions` as 12 fields, which fails without a reason.
  function test_shared_existingStrategies_cannotTrackARamsesPosition() public {
    SharedV3Strategy v3Strategy = new SharedV3Strategy(swapRouter);
    SharedAerodromeStrategy aeroStrategy = new SharedAerodromeStrategy(swapRouter);
    address[] memory strategies = new address[](2);
    strategies[0] = address(v3Strategy);
    strategies[1] = address(aeroStrategy);
    SharedVault vault = _sharedVault(strategies);
    uint256 tokenId = _mintAs(OWNER);
    assertEq(_positionWords(tokenId), 10);
    vm.prank(OWNER);
    IERC721(RAMSES_NFPM).approve(address(vault), tokenId);

    vm.expectRevert(bytes(""));
    v3Strategy.getPositionTokens(RAMSES_NFPM, tokenId);
    vm.prank(OWNER);
    vm.expectRevert(bytes(""));
    vault.recoverPosition(RAMSES_NFPM, tokenId, address(v3Strategy), WHYPE, HYPER_USDC);
    vm.expectRevert(bytes(""));
    aeroStrategy.getPositionTokens(RAMSES_NFPM, tokenId);
    vm.prank(OWNER);
    vm.expectRevert(bytes(""));
    vault.recoverPosition(RAMSES_NFPM, tokenId, address(aeroStrategy), WHYPE, HYPER_USDC);

    assertEq(vault.getPositionCount(), 0);
    assertEq(IERC721(RAMSES_NFPM).ownerOf(tokenId), OWNER);
  }

  /// And no shared strategy can claim RAM: none has a harvest operation (their operations stop at
  /// EXECUTE_INSTRUCTIONS = 2), so a fourth operation fails to decode.
  function test_shared_existingStrategies_haveNoWayToClaimRam() public {
    assertEq(uint8(type(SharedV3Strategy.OperationType).max), 2);
    assertEq(uint8(type(SharedAerodromeStrategy.OperationType).max), 2);

    SharedV3Strategy v3Strategy = new SharedV3Strategy(swapRouter);
    SharedAerodromeStrategy aeroStrategy = new SharedAerodromeStrategy(swapRouter);
    address[] memory strategies = new address[](2);
    strategies[0] = address(v3Strategy);
    strategies[1] = address(aeroStrategy);
    SharedVault vault = _sharedVault(strategies);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    bytes memory harvest = bytes.concat(abi.encode(uint256(3)), abi.encode(tokenIds, uint64(0)));

    vm.expectRevert(ISharedCommon.StrategyCallFailed.selector);
    _execute(vault, address(v3Strategy), harvest);
    vm.expectRevert(ISharedCommon.StrategyCallFailed.selector);
    _execute(vault, address(aeroStrategy), harvest);
  }
}
