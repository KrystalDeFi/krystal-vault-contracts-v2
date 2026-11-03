// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { IPrivateConfigManager } from "../../contracts/private-vault/interfaces/core/IPrivateConfigManager.sol";
import { RamsesFarmingStrategy } from "../../contracts/private-vault/strategies/farm/RamsesFarmingStrategy.sol";
import { V3UtilsStrategy } from "../../contracts/private-vault/strategies/lpv3/V3UtilsStrategy.sol";
import { IRamsesVoter } from "../../contracts/common/interfaces/protocols/ramses/IRamsesVoter.sol";
import { IV3UtilsRewardForward } from "../helpers/IV3UtilsRewardForward.sol";

/// @notice Smoke test of the Ramses configuration on Robinhood (configs/config_robinhood.ts and the deployment in
///         contracts-private.json) against the live chain. Ramses doesn't publish its Robinhood Voter (`ramsesVoter`
///         was read from the position manager's storage), so this pins it to the position manager and RAM Ramses
///         does publish, and checks that the configured V3Utils passes a Ramses position's RAM on (v3utils#63)
///         instead of keeping it. Forks the latest block (`ROBINHOOD_RPC_URL`, or the public RPC), so it's
///         non-hermetic and excluded from the offline CI gate; `checkRamsesConfig` (scripts/deployLogic-private.ts)
///         runs the same Voter and V3Utils checks before every Ramses strategy deployment.
contract RobinhoodRamsesConfigTest is Test {
  /// @dev `ramsesVoter` in configs/config_robinhood.ts.
  address internal constant VOTER = 0x30032D41868906f0376eC4D87B3D3Ac4064e7A97;
  /// @dev `v3UtilsAddress` in configs/config_robinhood.ts (the same V3Utils as on HyperEVM).
  address internal constant V3_UTILS = 0x8053e6e8b6CAB476D13060806141BE5bc71Bfc42;
  /// @dev Ramses' published Robinhood addresses (www.ramses.xyz/docs/contract-addresses).
  address internal constant RAMSES_NFPM = 0x2eBd7B85a4E08D5B508b04BA147976C94afE6590;
  address internal constant RAM = 0x5173D45A1191eE33cBB7D8c7e65f21B04eD54802;
  /// @dev The position manager keeps its Voter and RAM in storage, with no getter.
  uint256 internal constant NFPM_VOTER_SLOT = 14;
  uint256 internal constant NFPM_RAM_SLOT = 15;
  /// @dev The robinhood_mainnet deployment, read from contracts-private.json so a redeployment is checked too.
  address internal configManager;
  address internal ramsesFarmingStrategy;
  address internal v3UtilsStrategy;

  function setUp() public {
    vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", string("https://robinhood.api.pocket.network")));
    assertEq(block.chainid, 4663, "not a Robinhood RPC");
    string memory deployment = vm.readFile("contracts-private.json");
    configManager = vm.parseJsonAddress(deployment, ".robinhood_mainnet.privateConfigManager");
    ramsesFarmingStrategy = vm.parseJsonAddress(deployment, ".robinhood_mainnet.ramsesFarmingStrategy");
    v3UtilsStrategy = vm.parseJsonAddress(deployment, ".robinhood_mainnet.v3UtilsStrategy");
  }

  /// The configured Voter names the published position manager and RAM, and it's the Voter that position manager
  /// claims through: what the strategy reads at deployment is what Ramses pays out.
  function test_voter_matchesThePublishedPositionManagerAndRam() public view {
    assertEq(IRamsesVoter(VOTER).nfpManager(), RAMSES_NFPM, "Voter's position manager");
    assertEq(IRamsesVoter(VOTER).ram(), RAM, "Voter's RAM");
    assertEq(_loadAddress(RAMSES_NFPM, NFPM_VOTER_SLOT), VOTER, "position manager's Voter");
    assertEq(_loadAddress(RAMSES_NFPM, NFPM_RAM_SLOT), RAM, "position manager's RAM");
  }

  /// V3Utils holds a Ramses position's NFT while it operates on it, so Ramses pays the position's RAM to V3Utils,
  /// which has to pass it on.
  function test_configuredV3Utils_passesARamsesPositionsRamOn() public view {
    assertEq(IV3UtilsRewardForward(V3_UTILS).positionRewardToken(RAMSES_NFPM), RAM);
  }

  /// A strategy deployed from the config, and the deployed one, claim RAM through the published position manager.
  function test_ramsesFarmingStrategy_claimsRamThroughThePublishedPositionManager() public {
    RamsesFarmingStrategy fresh = new RamsesFarmingStrategy(VOTER, configManager);
    assertEq(fresh.nfpm(), RAMSES_NFPM);
    assertEq(fresh.rewardToken(), RAM);

    RamsesFarmingStrategy deployed = RamsesFarmingStrategy(ramsesFarmingStrategy);
    assertEq(deployed.nfpm(), RAMSES_NFPM);
    assertEq(deployed.rewardToken(), RAM);
    assertEq(address(deployed.configManager()), configManager);
  }

  /// Vaults can call both strategies, and their V3Utils operations go through the configured V3Utils.
  function test_deployment_whitelistsBothStrategiesAndUsesTheConfiguredV3Utils() public view {
    assertTrue(IPrivateConfigManager(configManager).isWhitelistedTarget(ramsesFarmingStrategy), "Ramses strategy");
    assertTrue(IPrivateConfigManager(configManager).isWhitelistedTarget(v3UtilsStrategy), "V3Utils strategy");
    assertEq(V3UtilsStrategy(v3UtilsStrategy).v3utils(), V3_UTILS);
  }

  function _loadAddress(address target, uint256 slot) internal view returns (address) {
    return address(uint160(uint256(vm.load(target, bytes32(slot)))));
  }
}
