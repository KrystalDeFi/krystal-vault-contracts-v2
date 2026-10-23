// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, USER, WETH, USDC } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { V3UtilsStrategy } from "../../contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { AerodromeFarmingStrategy } from "../../contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol";
import { IAeroCLGauge } from "../../contracts/common/interfaces/protocols/aerodrome/IAeroCLGauge.sol";
import { ICLGauge } from "../../contracts/common/interfaces/protocols/aerodrome/ICLGauge.sol";
import { ICLPool } from "../../contracts/common/interfaces/protocols/aerodrome/ICLPool.sol";

interface IAeroGaugeManager {
  struct GaugeCreationRequest {
    address creator;
    address gaugeFactory;
    address target;
    bytes factoryData;
    bool activate;
  }

  function createGauge(GaugeCreationRequest calldata request) external returns (address gauge);
}

interface IAeroLeafVoter {
  function settleGauge(address gauge) external returns (uint256 cumulativeRewardShare);
}

interface IAeroGaugeSettlement {
  function lastCumulativeRewardShare() external view returns (uint256);
}

interface IV3UtilsAdmin {
  function setWhitelistNfpm(address[] calldata nfpms, bool isWhitelist) external;
}

/// @notice Private vault on Aero (the merged Aerodrome + Velodrome, MetaDEX Slipstream) on a Base fork after its
///         2026-10-21 launch: LP through the real V3Utils on the Aero NFPM, farming through AerodromeFarmingStrategy
///         against a real Aero CLGauge.
contract PrivateVaultAeroIntegrationTest is TestCommon {
  uint256 constant AERO_FORK_BLOCK = 52_900_000;

  address constant AERO_NFPM = 0x4857DB576eE0e45F10525eC59527BfD10beeC60b;
  address constant AERO_GAUGE_FACTORY = 0xf437f62053ACB121665b8fDBfeA8F214FB8E589d;
  address constant AERO = 0x3f5bF3EdAc59d650D8fDf9657a71F2f904A3a4Ee; // what Base's Aero gauges pay
  address constant LEAF_VOTER = 0x382409fad8503FbCdbB27A4211551fa03e884078;
  address constant GAUGE_MANAGER = 0xbF234b32c5e58868243A4a14831626f3EdE7b183;
  // A GovernanceCreationModule registered on the GaugeManager at AERO_FORK_BLOCK (the documented 0xD035… instance,
  // same code, was registered later).
  address constant GOVERNANCE_CREATION_MODULE = 0xCeb882F3BE8F8Be37E573c0C577d9eFc9c706596;
  address constant WETH_USDC_POOL = 0x2A430bEbD2082d8e05D56d64DEDE8944279bbC24; // tickSpacing 100
  address constant WETH_USDC_POOL_TS50 = 0x4A7af46bC8aBc00048c6c7920a1488DAF568366c; // tickSpacing 50
  address constant BASE_XAERO = 0x6CdDa0E730744DC6fF67654B35350Adad05EceE7; // Base LeafVoter's receipt token
  address constant LEGACY_GAUGE_FACTORY = 0xD30677bd8dd15132F251Cb54CbDA552d2A05Fb08; // Aerodrome
  address constant V3_UTILS = 0xb4acbC082b5e7dEd571c98EE4257778a9D784B36;
  address constant V3_UTILS_ADMIN = 0x9A99252A76f7B40Cbf2002a8dB2977C85fA306DF;

  uint8 constant PROTOCOL = 3; // V3Utils AERODROME: the Aero NFPM keeps the Slipstream ABI
  int24 constant TICK_SPACING = 100;
  int24 constant TICK_LOWER = -887_000;
  int24 constant TICK_UPPER = 887_000;

  PrivateConfigManager configManager;
  PrivateVault vault;
  V3UtilsStrategy v3UtilsStrategy;
  AerodromeFarmingStrategy farmingStrategy;
  address gauge;

  address vaultOwner = USER;
  address operator = makeAddr("operator");
  address feeRecipient = makeAddr("feeRecipient");

  function setUp() public {
    vm.selectFork(vm.createFork(vm.envString("RPC_URL"), AERO_FORK_BLOCK));

    // No Aero CL gauge exists yet at this block. Create one the way Aero governance does: through the
    // GaugeManager, which deploys it from the CLGaugeFactory and registers it on the LeafVoter.
    vm.prank(GOVERNANCE_CREATION_MODULE);
    gauge = IAeroGaugeManager(GAUGE_MANAGER).createGauge(
      IAeroGaugeManager.GaugeCreationRequest({
        creator: address(this),
        gaugeFactory: AERO_GAUGE_FACTORY,
        target: WETH_USDC_POOL,
        factoryData: "",
        activate: true
      })
    );
    assertEq(ICLPool(WETH_USDC_POOL).gauge(), gauge, "pool linked to its new gauge");

    // The ops step Aero needs on every chain: V3Utils must whitelist the Aero NFPM.
    address[] memory nfpms = new address[](1);
    nfpms[0] = AERO_NFPM;
    vm.prank(V3_UTILS_ADMIN);
    IV3UtilsAdmin(V3_UTILS).setWhitelistNfpm(nfpms, true);

    address[] memory callers = new address[](1);
    callers[0] = operator;
    configManager = new PrivateConfigManager();
    configManager.initialize(address(this), new address[](0), callers, feeRecipient);

    v3UtilsStrategy = new V3UtilsStrategy(V3_UTILS);
    farmingStrategy = new AerodromeFarmingStrategy(AERO_GAUGE_FACTORY, address(configManager), AERO);

    address[] memory targets = new address[](2);
    targets[0] = address(v3UtilsStrategy);
    targets[1] = address(farmingStrategy);
    configManager.setWhitelistTargets(targets, true);

    vault = new PrivateVault();
    vault.initialize(vaultOwner, address(configManager), "aero");

    setErc20Balance(WETH, address(vault), 1 ether);
    setErc20Balance(USDC, address(vault), 4000e6);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------------------------

  function _multicall(address[] memory targets, bytes[] memory calls) internal {
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](targets.length);
    for (uint256 i; i < targets.length; i++) {
      callTypes[i] = IPrivateCommon.CallType.DELEGATECALL;
    }
    vm.prank(operator);
    vault.multicall(targets, new uint256[](targets.length), calls, callTypes);
  }

  function _exec(address target, bytes memory data) internal {
    address[] memory targets = new address[](1);
    targets[0] = target;
    bytes[] memory calls = new bytes[](1);
    calls[0] = data;
    _multicall(targets, calls);
  }

  /// @dev V3Utils mint on the Aero NFPM and stake the new position in one multicall, as the automation does.
  function _zapIntoGauge() internal returns (uint256 tokenId) {
    (address[] memory targets, bytes[] memory calls) = _zapCalls(TICK_SPACING);
    _multicall(targets, calls);

    // The gauge's staked set for the vault holds exactly the position just staked.
    (bool ok, bytes memory ret) =
      gauge.staticcall(abi.encodeWithSignature("stakedByIndex(address,uint256)", address(vault), uint256(0)));
    require(ok, "no staked position");
    tokenId = abi.decode(ret, (uint256));
  }

  /// @dev The two multicall steps of a zap into the WETH/USDC pool with `tickSpacing`: mint, then stake it.
  function _zapCalls(int24 tickSpacing) internal view returns (address[] memory targets, bytes[] memory calls) {
    address[] memory tokens = new address[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.5 ether;
    amounts[1] = 1500e6;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: PROTOCOL,
      nfpm: AERO_NFPM,
      token0: WETH,
      token1: USDC,
      fee: 0,
      tickSpacing: tickSpacing,
      tickLower: TICK_LOWER,
      tickUpper: TICK_UPPER,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: 0.5 ether,
      amount1: 1500e6,
      amount2: 0,
      recipient: address(vault),
      deadline: block.timestamp + 300,
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

    targets = new address[](2);
    targets[0] = address(v3UtilsStrategy);
    targets[1] = address(farmingStrategy);
    calls = new bytes[](2);
    calls[0] = abi.encodeCall(V3UtilsStrategy.swapAndMint, (params, 0, tokens, amounts, false));
    calls[1] = abi.encodeCall(AerodromeFarmingStrategy.deposit, (0)); // 0 = the position just minted
  }

  function _harvest(uint256 tokenId) internal {
    _exec(address(farmingStrategy), abi.encodeCall(AerodromeFarmingStrategy.harvest, (tokenId, 0, 0, false)));
  }

  function _withdraw(uint256 tokenId) internal {
    _exec(address(farmingStrategy), abi.encodeCall(AerodromeFarmingStrategy.withdraw, (tokenId, 0, 0, false)));
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------------------------------------------

  /// The premise of this change: Aero gauges dropped the legacy claim API the strategy used to call.
  function test_aeroGauge_hasNoLegacyRewardApi() public {
    vm.expectRevert();
    ICLGauge(gauge).rewardToken();
  }

  function test_aero_strategyBindsToRealFactories() public {
    assertEq(farmingStrategy.nfpm(), AERO_NFPM);
    assertEq(farmingStrategy.leafVoter(), LEAF_VOTER);
    assertEq(farmingStrategy.emissionToken(), AERO);

    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(AERO_GAUGE_FACTORY, address(configManager), address(0));

    // Base's root handler redeems the receipt token for AERO, so the vault never holds xAERO here.
    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(AERO_GAUGE_FACTORY, address(configManager), BASE_XAERO);

    // A legacy Aerodrome factory ignores the emission token the deploy script passes every factory.
    AerodromeFarmingStrategy legacy = new AerodromeFarmingStrategy(LEGACY_GAUGE_FACTORY, address(configManager), AERO);
    assertEq(legacy.leafVoter(), address(0));
    assertEq(legacy.emissionToken(), address(0));
  }

  /// A gauge registered without activation earns no emissions, so staking into it is refused.
  function test_aero_deposit_refusesInactiveGauge() public {
    vm.prank(GOVERNANCE_CREATION_MODULE);
    address inactiveGauge = IAeroGaugeManager(GAUGE_MANAGER).createGauge(
      IAeroGaugeManager.GaugeCreationRequest({
        creator: address(this),
        gaugeFactory: AERO_GAUGE_FACTORY,
        target: WETH_USDC_POOL_TS50,
        factoryData: "",
        activate: false
      })
    );
    assertEq(ICLPool(WETH_USDC_POOL_TS50).gauge(), inactiveGauge);

    (address[] memory targets, bytes[] memory calls) = _zapCalls(50);
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](2);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;
    callTypes[1] = IPrivateCommon.CallType.DELEGATECALL;
    vm.prank(operator);
    vm.expectRevert("Gauge not active");
    vault.multicall(targets, new uint256[](2), calls, callTypes);
  }

  function test_aero_zapIntoGauge_stakesV3UtilsPosition() public {
    uint256 tokenId = _zapIntoGauge();

    assertEq(IERC721(AERO_NFPM).ownerOf(tokenId), gauge);
    assertTrue(ICLGauge(gauge).stakedContains(address(vault), tokenId));
  }

  function test_aero_harvest_claimsThroughClaimEmissions() public {
    uint256 tokenId = _zapIntoGauge();
    vm.warp(block.timestamp + 1 days);
    vm.roll(block.number + 43_200);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    vm.expectCall(gauge, abi.encodeCall(IAeroCLGauge.claimEmissions, (address(vault), address(vault), tokenIds)));
    _harvest(tokenId);

    assertTrue(ICLGauge(gauge).stakedContains(address(vault), tokenId), "harvest keeps the position staked");
  }

  function test_aero_withdraw_returnsNftToVault() public {
    uint256 tokenId = _zapIntoGauge();
    vm.warp(block.timestamp + 1 days);
    vm.roll(block.number + 43_200);

    _withdraw(tokenId);

    assertEq(IERC721(AERO_NFPM).ownerOf(tokenId), address(vault));
    assertFalse(ICLGauge(gauge).stakedContains(address(vault), tokenId));
  }

  function test_aero_emergencyWithdraw_revertsWhileAeroKeepsItDisabled() public {
    uint256 tokenId = _zapIntoGauge();

    vm.expectRevert(bytes("NE"));
    _exec(address(farmingStrategy), abi.encodeCall(AerodromeFarmingStrategy.emergencyWithdraw, (tokenId)));
    assertEq(IERC721(AERO_NFPM).ownerOf(tokenId), gauge);
  }

  /// Once Aero governance switches emergency withdrawals on, the strategy unstakes through the real gauge path,
  /// forfeiting the position's emissions.
  function test_aero_emergencyWithdraw_returnsNftOnceAeroEnablesIt() public {
    uint256 tokenId = _zapIntoGauge();
    vm.warp(block.timestamp + 1 days);
    vm.roll(block.number + 43_200);
    vm.mockCall(AERO_GAUGE_FACTORY, abi.encodeWithSignature("emergencyWithdrawEnabled()"), abi.encode(true));

    uint256 vaultAeroBefore = IERC20(AERO).balanceOf(address(vault));
    _exec(address(farmingStrategy), abi.encodeCall(AerodromeFarmingStrategy.emergencyWithdraw, (tokenId)));

    assertEq(IERC721(AERO_NFPM).ownerOf(tokenId), address(vault));
    assertFalse(ICLGauge(gauge).stakedContains(address(vault), tokenId));
    assertEq(IERC20(AERO).balanceOf(address(vault)), vaultAeroBefore, "emissions are forfeited, not paid");
  }

  /// Emissions accrue but the LeafVoter can't mint them (here: the new gauge has no allocation, so the real
  /// `mintEmissions` hits CeilingExceeded). The withdrawal must still return the NFT, with the emissions deferred.
  function test_aero_withdraw_duringMintFailure_returnsNftAndDefersEmissions() public {
    uint256 tokenId = _zapIntoGauge();
    vm.warp(block.timestamp + 1 days);
    vm.roll(block.number + 43_200);

    // Report 1 AERO of accrued emissions for the gauge; the pool hands it to the only staked position.
    uint256 settled = IAeroGaugeSettlement(gauge).lastCumulativeRewardShare();
    vm.mockCall(LEAF_VOTER, abi.encodeCall(IAeroLeafVoter.settleGauge, (gauge)), abi.encode(settled + 1e18));

    uint256 vaultAeroBefore = IERC20(AERO).balanceOf(address(vault));
    _withdraw(tokenId);

    assertEq(IERC721(AERO_NFPM).ownerOf(tokenId), address(vault), "NFT is back despite the mint failure");
    uint256 deferred = IAeroCLGauge(gauge).deferredEmissions(address(vault));
    assertApproxEqAbs(deferred, 1e18, 1e6, "the position's emissions are deferred, not lost");
    assertEq(IERC20(AERO).balanceOf(address(vault)), vaultAeroBefore);
    assertEq(IERC20(AERO).balanceOf(feeRecipient), 0);

    // Harvesting the withdrawn position claims only the deferred emissions; while minting still fails the
    // harvest reverts and leaves them in place.
    vm.expectCall(
      gauge, abi.encodeCall(IAeroCLGauge.claimEmissions, (address(vault), address(vault), new uint256[](0)))
    );
    vm.expectRevert(bytes4(keccak256("CeilingExceeded()")));
    _harvest(tokenId);
    assertEq(IAeroCLGauge(gauge).deferredEmissions(address(vault)), deferred);
  }
}
