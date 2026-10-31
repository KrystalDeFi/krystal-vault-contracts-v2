// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { RamsesFarmingStrategy } from "../../contracts/private-vault/strategies/farm/RamsesFarmingStrategy.sol";
import {
  MockRamsesToken,
  MockRamsesPool,
  MockRamsesVoter,
  MockRamsesRewardValidator,
  MockRamsesGauge,
  MockRamsesNfpm
} from "../helpers/RamsesMocks.sol";

contract RamsesFarmingStrategyTest is Test {
  uint256 internal constant Q64 = 0x10000000000000000;
  address internal constant OWNER = address(0xA11CE);
  address internal constant OPERATOR = address(0x0FE7A70);
  uint256 internal constant REWARD = 100e18;
  uint256 internal constant ANTI_SYBIL_THRESHOLD = 299;

  address internal feeRecipient = makeAddr("feeRecipient");
  address internal r33 = makeAddr("r33");
  uint64 internal rewardFeeX64 = uint64(Q64 * 5 / 100);
  uint64 internal gasFeeX64 = uint64(Q64 / 100);

  PrivateConfigManager internal configManager;
  PrivateVault internal vault;

  MockRamsesToken internal ram;
  MockRamsesToken internal xRam;
  MockRamsesPool internal pool;
  MockRamsesVoter internal voter;
  MockRamsesNfpm internal nfpm;
  MockRamsesRewardValidator internal validator;
  MockRamsesGauge internal gauge;
  RamsesFarmingStrategy internal strategy;

  function setUp() public {
    address[] memory callers = new address[](1);
    callers[0] = OPERATOR;
    configManager = new PrivateConfigManager();
    configManager.initialize(address(this), new address[](0), callers, feeRecipient);

    vault = new PrivateVault();
    vault.initialize(OWNER, address(configManager), "ramses");

    ram = new MockRamsesToken("RAM");
    xRam = new MockRamsesToken("xRAM");
    MockRamsesToken tokenA = new MockRamsesToken("WHYPE");
    MockRamsesToken tokenB = new MockRamsesToken("USDC");
    (address token0, address token1) =
      address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

    pool = new MockRamsesPool(token0, token1, 50);
    voter = new MockRamsesVoter(address(ram));
    nfpm = new MockRamsesNfpm(voter);
    voter.setNfpManager(address(nfpm));
    validator = new MockRamsesRewardValidator(address(nfpm), ANTI_SYBIL_THRESHOLD);
    gauge = new MockRamsesGauge(address(nfpm), address(pool), address(validator), r33);
    voter.setGauge(address(pool), address(gauge));

    strategy = new RamsesFarmingStrategy(address(voter), address(configManager));

    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.setWhitelistTargets(targets, true);
  }

  /// A vault position whose anti-sybil timer has already cleared, with `pending` RAM to claim.
  function _farmingPosition(uint256 pending) internal returns (uint256 tokenId) {
    tokenId = nfpm.mintPositionTo(address(vault), address(pool), -1000, 1000, 1e18);
    vm.warp(vm.getBlockTimestamp() + 1 days);
    gauge.setPending(tokenId, address(ram), pending);
  }

  function _harvest(uint256 tokenId, bool toOwner) internal {
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    bytes[] memory calls = new bytes[](1);
    calls[0] = abi.encodeCall(RamsesFarmingStrategy.harvest, (tokenId, rewardFeeX64, gasFeeX64, toOwner));
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;
    vm.prank(OPERATOR);
    vault.multicall(targets, new uint256[](1), calls, callTypes);
  }

  function _fee(uint256 amount) internal view returns (uint256) {
    return Math.mulDiv(amount, rewardFeeX64, Q64) + Math.mulDiv(amount, gasFeeX64, Q64);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------------------------------------------

  function test_constructor_readsPositionManagerAndRewardTokenFromVoter() public view {
    assertEq(strategy.nfpm(), address(nfpm));
    assertEq(strategy.rewardToken(), address(ram));
    assertEq(address(strategy.configManager()), address(configManager));
  }

  function test_constructor_revertsWhen_voterIsZero() public {
    vm.expectRevert("Invalid voter");
    new RamsesFarmingStrategy(address(0), address(configManager));
  }

  function test_constructor_revertsWhen_configManagerIsZero() public {
    vm.expectRevert("Invalid config manager");
    new RamsesFarmingStrategy(address(voter), address(0));
  }

  /// A Voter not wired to a position manager yet (Ramses deploys CL first, governance later) can't be farmed.
  function test_constructor_revertsWhen_voterHasNoPositionManager() public {
    MockRamsesVoter unwired = new MockRamsesVoter(address(ram));
    vm.expectRevert("Invalid voter");
    new RamsesFarmingStrategy(address(unwired), address(configManager));
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Harvest
  // ---------------------------------------------------------------------------------------------------------------

  function test_harvest_claimsRamAndTakesFees() public {
    uint256 tokenId = _farmingPosition(REWARD);

    _harvest(tokenId, false);

    assertEq(ram.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(ram.balanceOf(address(vault)), REWARD - _fee(REWARD));
    assertEq(nfpm.ownerOf(tokenId), address(vault), "Ramses gauges never take the NFT");
    assertEq(gauge.earned(address(ram), tokenId), 0);
  }

  function test_harvest_toVaultOwner() public {
    uint256 tokenId = _farmingPosition(REWARD);

    _harvest(tokenId, true);

    assertEq(ram.balanceOf(OWNER), REWARD - _fee(REWARD));
    assertEq(ram.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(ram.balanceOf(address(vault)), 0);
  }

  /// xRAM can't be transferred out of the vault, so the harvest never claims it: it stays in the gauge.
  function test_harvest_claimsRamOnly() public {
    uint256 tokenId = _farmingPosition(REWARD);
    gauge.setPending(tokenId, address(xRam), 7e18);

    _harvest(tokenId, true);

    assertEq(xRam.balanceOf(address(vault)), 0);
    assertEq(xRam.balanceOf(OWNER), 0);
    assertEq(gauge.earned(address(xRam), tokenId), 7e18);
  }

  function test_harvest_emitsHarvested() public {
    uint256 tokenId = _farmingPosition(REWARD);

    vm.expectEmit(true, true, false, true, address(vault));
    emit RamsesFarmingStrategy.RamsesFarmingRewardsHarvested(
      tokenId, address(nfpm), REWARD, REWARD - _fee(REWARD), OPERATOR
    );
    _harvest(tokenId, false);
  }

  /// Claiming within the anti-sybil window after a liquidity change forfeits the RAM to r33. The harvest measures
  /// what actually arrived, so it neither reverts nor charges a fee on the forfeited amount.
  function test_harvest_whenClaimIsForfeited_paysAndChargesNothing() public {
    uint256 tokenId = nfpm.mintPositionTo(address(vault), address(pool), -1000, 1000, 1e18);
    gauge.setPending(tokenId, address(ram), REWARD);

    _harvest(tokenId, true);

    assertEq(ram.balanceOf(r33), REWARD, "forfeited to r33");
    assertEq(ram.balanceOf(feeRecipient), 0);
    assertEq(ram.balanceOf(OWNER), 0);
    assertEq(ram.balanceOf(address(vault)), 0);
  }

  function test_harvest_revertsWhen_poolHasNoGauge() public {
    uint256 tokenId = _farmingPosition(REWARD);
    voter.setGauge(address(pool), address(0));

    vm.expectRevert();
    _harvest(tokenId, false);
  }

  function test_harvest_revertsWhen_vaultDoesNotHoldThePosition() public {
    uint256 tokenId = nfpm.mintPositionTo(address(0xB0B), address(pool), -1000, 1000, 1e18);
    vm.warp(vm.getBlockTimestamp() + 1 days);
    gauge.setPending(tokenId, address(ram), REWARD);

    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(vault), tokenId));
    _harvest(tokenId, false);
  }

  /// Whatever arrives is split exactly: each operator fee is its rate of the claim (rounded down) and the rest is kept
  /// or forwarded, while RAM the vault already held is never touched. Rates that add up past the claim revert the
  /// harvest rather than pay the excess out of that RAM.
  function testFuzz_harvest_splitsExactlyWhatArrived(
    uint256 earned,
    uint256 held,
    uint64 rewardFee,
    uint64 gasFee,
    bool toOwner
  ) public {
    earned = bound(earned, 0, 1e36);
    held = bound(held, 0, 1e36);
    (rewardFeeX64, gasFeeX64) = (rewardFee, gasFee);
    ram.mint(address(vault), held);
    uint256 tokenId = _farmingPosition(earned);
    uint256 fee = _fee(earned);

    if (fee > earned) {
      vm.expectRevert();
      _harvest(tokenId, toOwner);
      return;
    }
    _harvest(tokenId, toOwner);

    assertEq(ram.balanceOf(feeRecipient), fee);
    assertEq(ram.balanceOf(OWNER), toOwner ? earned - fee : 0);
    assertEq(ram.balanceOf(address(vault)), held + (toOwner ? 0 : earned - fee));
  }
}
