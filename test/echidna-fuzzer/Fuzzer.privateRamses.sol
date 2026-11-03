// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * RamsesFarmingStrategy assertion-mode Echidna harness: a real PrivateVault + PrivateConfigManager harvesting RAM
 * through RamsesFarmingStrategy against the RamsesMocks Ramses stack (claims go through the position manager to the
 * NFT's owner; a gauge forfeits a claim made within the anti-sybil window of the position's last liquidity change).
 *
 * Sequences interleave RAM and xRAM accrual, time, new positions (each opening a fresh window), RAM the vault already
 * holds, the gauge coming and going, and harvests with any fee rates, recipients and positions, including one the vault
 * doesn't own. Each harvest is checked against what the gauge reported just before it:
 *  - a harvest of a vault position in a gauged pool reverts only when the fee rates add up past the claim;
 *  - it then claims exactly what the position earned (inside the window the gauge forfeits all of it and nothing is
 *    charged), sends the fee recipient each rate of the claim, and keeps or forwards exactly the rest;
 *  - RAM the vault already held is never charged or moved, xRAM is never claimed, the NFT never leaves the vault;
 *  - a harvest of a position the vault doesn't own, or in a pool without a gauge, reverts.
 *
 * To run:
 *   echidna test/echidna-fuzzer/Fuzzer.privateRamses.sol \
 *     --config test/echidna-fuzzer/config.privateRamses.yaml --contract PrivateRamsesFuzzer
 */

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IHevm } from "./IHevm.sol";

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

contract PrivateRamsesFuzzer {
  IHevm internal constant HEVM = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
  uint256 internal constant Q64 = 0x10000000000000000;
  uint256 internal constant ANTI_SYBIL_THRESHOLD = 299;
  uint256 internal constant MAX_ACCRUAL = 1e24;
  uint256 internal constant MAX_POSITIONS = 6;
  address internal constant OWNER = address(0xA11CE);
  address internal constant FEE_RECIPIENT = address(0xFEE);
  address internal constant STRANGER = address(0xBAD);
  address internal constant R33 = address(0x0033);

  struct Balances {
    uint256 feeRecipient;
    uint256 owner;
    uint256 vault;
    uint256 r33;
    uint256 vaultXRam;
    uint256 ownerXRam;
  }

  MockRamsesToken public ram;
  MockRamsesToken public xRam;
  MockRamsesPool public pool;
  MockRamsesVoter public voter;
  MockRamsesNfpm public nfpm;
  MockRamsesGauge public gauge;
  RamsesFarmingStrategy public strategy;
  PrivateVault public vault;
  uint256[] public tokenIds;
  uint256 public strangerTokenId;

  constructor() {
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
    MockRamsesRewardValidator validator = new MockRamsesRewardValidator(address(nfpm), ANTI_SYBIL_THRESHOLD);
    gauge = new MockRamsesGauge(address(nfpm), address(pool), address(validator), R33);
    voter.setGauge(address(pool), address(gauge));

    PrivateConfigManager configManager = new PrivateConfigManager();
    address[] memory callers = new address[](1);
    callers[0] = address(this);
    configManager.initialize(address(this), new address[](0), callers, FEE_RECIPIENT);
    strategy = new RamsesFarmingStrategy(address(voter), address(configManager));
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.setWhitelistTargets(targets, true);

    vault = new PrivateVault();
    vault.initialize(OWNER, address(configManager), "ramses");
    tokenIds.push(nfpm.mintPositionTo(address(vault), address(pool), -1000, 1000, 1e18));
    strangerTokenId = nfpm.mintPositionTo(STRANGER, address(pool), -1000, 1000, 1e18);
  }

  // -------------------------------------------------------------------------
  // Environment
  // -------------------------------------------------------------------------

  function accrue(uint8 idx, uint256 amount) external {
    _accrue(_tokenId(idx), address(ram), amount);
  }

  function accrueXRam(uint8 idx, uint256 amount) external {
    _accrue(_tokenId(idx), address(xRam), amount);
  }

  function accrueStranger(uint256 amount) external {
    _accrue(strangerTokenId, address(ram), amount);
  }

  function elapse(uint256 secs) external {
    HEVM.warp(block.timestamp + secs % 1 days);
  }

  /// A new vault position, whose anti-sybil window opens now.
  function mintPosition() external {
    if (tokenIds.length < MAX_POSITIONS) {
      tokenIds.push(nfpm.mintPositionTo(address(vault), address(pool), -1000, 1000, 1e18));
    }
  }

  function donateRam(uint256 amount) external {
    ram.mint(address(vault), amount % MAX_ACCRUAL);
  }

  function setGauged(bool gauged) external {
    voter.setGauge(address(pool), gauged ? address(gauge) : address(0));
  }

  // -------------------------------------------------------------------------
  // Harvests
  // -------------------------------------------------------------------------

  function harvest(uint8 idx, uint64 rewardFeeX64, uint64 gasFeeX64, bool toOwner) external {
    uint256 tokenId = _tokenId(idx);
    bool gauged = voter.gaugeForPool(address(pool)) != address(0);
    uint256 earned = gauge.earned(address(ram), tokenId);
    uint256 xEarned = gauge.earned(address(xRam), tokenId);
    bool forfeited = block.timestamp < uint256(nfpm.positionLastModified(tokenId)) + ANTI_SYBIL_THRESHOLD;
    uint256 claimed = forfeited ? 0 : earned;
    uint256 fee = Math.mulDiv(claimed, rewardFeeX64, Q64) + Math.mulDiv(claimed, gasFeeX64, Q64);
    Balances memory before = _balances();

    try vault.multicall(
      _targets(), new uint256[](1), _harvestCall(tokenId, rewardFeeX64, gasFeeX64, toOwner), _delegatecall()
    ) {
      assert(gauged && fee <= claimed);
      Balances memory afterHarvest = _balances();
      assert(afterHarvest.feeRecipient == before.feeRecipient + fee);
      assert(afterHarvest.owner == before.owner + (toOwner ? claimed - fee : 0));
      assert(afterHarvest.vault == before.vault + (toOwner ? 0 : claimed - fee));
      assert(afterHarvest.r33 == before.r33 + (forfeited ? earned : 0));
      assert(afterHarvest.vaultXRam == 0 && afterHarvest.ownerXRam == 0);
      assert(gauge.earned(address(ram), tokenId) == 0);
      assert(gauge.earned(address(xRam), tokenId) == xEarned);
      assert(nfpm.ownerOf(tokenId) == address(vault));
    } catch {
      assert(!gauged || fee > claimed);
    }
  }

  function harvestStrangersPosition(uint64 rewardFeeX64, uint64 gasFeeX64, bool toOwner) external {
    try vault.multicall(
      _targets(), new uint256[](1), _harvestCall(strangerTokenId, rewardFeeX64, gasFeeX64, toOwner), _delegatecall()
    ) {
      assert(false);
    } catch { }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  function _accrue(uint256 tokenId, address token, uint256 amount) internal {
    gauge.setPending(tokenId, token, gauge.earned(token, tokenId) + amount % MAX_ACCRUAL);
  }

  function _tokenId(uint8 idx) internal view returns (uint256) {
    return tokenIds[idx % tokenIds.length];
  }

  function _balances() internal view returns (Balances memory b) {
    b.feeRecipient = ram.balanceOf(FEE_RECIPIENT);
    b.owner = ram.balanceOf(OWNER);
    b.vault = ram.balanceOf(address(vault));
    b.r33 = ram.balanceOf(R33);
    b.vaultXRam = xRam.balanceOf(address(vault));
    b.ownerXRam = xRam.balanceOf(OWNER);
  }

  function _targets() internal view returns (address[] memory targets) {
    targets = new address[](1);
    targets[0] = address(strategy);
  }

  function _harvestCall(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool toOwner)
    internal
    pure
    returns (bytes[] memory calls)
  {
    calls = new bytes[](1);
    calls[0] = abi.encodeCall(RamsesFarmingStrategy.harvest, (tokenId, rewardFeeX64, gasFeeX64, toOwner));
  }

  function _delegatecall() internal pure returns (IPrivateCommon.CallType[] memory callTypes) {
    callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;
  }
}
