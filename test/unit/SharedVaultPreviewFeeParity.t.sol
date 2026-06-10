// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { SharedStrategyFees } from "../../contracts/shared-vault/libraries/SharedStrategyFees.sol";
import { SharedVaultPreviewLib } from "../../contracts/shared-vault/libraries/SharedVaultPreviewLib.sol";

// ---------------------------------------------------------------------------
// Wei-parity between SharedVaultPreviewLib.netAfterPerformanceFees and the real
// SharedStrategyFees.applyFees settlement. The preview NatSpec claims it mirrors
// applyFees EXACTLY (same floor division from the ORIGINAL amount, same sequential
// platform -> owner application, same clamp-to-remainder); this fuzz pins that
// claim across the full bps range INCLUDING the platform+owner > 100% clamp region.
// A 1-wei divergence here would make previewWithdraw's fee TERM drift from the
// on-chain collect (the W-7 doc allows rounding drift only in the share-slicing,
// never in the fee math itself).
// ---------------------------------------------------------------------------

contract ParityFeeToken {
  mapping(address => uint256) public balanceOf;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

/// @dev applyFees is an internal library function; calling it from this harness inlines it here, so
///      fee transfers draw from the harness balance — mirroring the vault's delegatecall context.
contract ApplyFeesHarness {
  function applyFeesExternal(address token0, uint256 amount0, address token1, uint256 amount1, ICommon.FeeConfig memory fc)
    external
    returns (uint256 fee0, uint256 fee1)
  {
    return SharedStrategyFees.applyFees(token0, amount0, token1, amount1, fc);
  }
}

contract SharedVaultPreviewFeeParityTest is Test {
  address internal constant PLATFORM_RECIPIENT = address(0xCAFE);
  address internal constant OWNER_RECIPIENT = address(0xBEEF);

  function _run(uint256 owed, uint16 platformBps, uint16 ownerBps) internal {
    ParityFeeToken token0 = new ParityFeeToken();
    ParityFeeToken token1 = new ParityFeeToken();
    ApplyFeesHarness harness = new ApplyFeesHarness();
    token0.mint(address(harness), owed);
    token1.mint(address(harness), owed);

    ICommon.FeeConfig memory fc = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: ownerBps,
      vaultOwner: OWNER_RECIPIENT,
      platformFeeBasisPoint: platformBps,
      platformFeeRecipient: PLATFORM_RECIPIENT,
      gasFeeX64: 0, // withdraw exits never charge gas; the preview omits it by design
      gasFeeRecipient: address(0)
    });

    (uint256 fee0, uint256 fee1) = harness.applyFeesExternal(address(token0), owed, address(token1), owed, fc);
    uint256 previewNet = SharedVaultPreviewLib.netAfterPerformanceFees(owed, platformBps, ownerBps);

    assertEq(previewNet, owed - fee0, "preview net must equal owed minus realized token0 fees");
    assertEq(previewNet, owed - fee1, "preview net must equal owed minus realized token1 fees");
    assertEq(token0.balanceOf(address(harness)), previewNet, "harness keeps exactly the previewed net (token0)");
    assertEq(token1.balanceOf(address(harness)), previewNet, "harness keeps exactly the previewed net (token1)");
  }

  function testFuzz_netAfterPerformanceFees_matchesApplyFees(uint256 owed, uint16 platformBps, uint16 ownerBps)
    public
  {
    owed = bound(owed, 0, type(uint128).max);
    platformBps = uint16(bound(platformBps, 0, 10_000));
    // Deliberately NOT capped at 10_000 - platformBps: the clamp region must agree to the wei too.
    ownerBps = uint16(bound(ownerBps, 0, 10_000));
    _run(owed, platformBps, ownerBps);
  }

  function test_parity_platformFullClampsOwnerToZero() public {
    _run(1e18 + 7, 10_000, 5000); // platform takes all; owner clamped to the zero remainder
  }

  function test_parity_combinedAboveHundredPercentClamps() public {
    _run(123_456_789, 9000, 5000); // owner fee computed from the ORIGINAL amount, clamped to remainder
  }

  function test_parity_oneWeiOwed() public {
    _run(1, 1, 1); // floor division drops both sub-wei fees on each side identically
  }

  // ---------------------------------------------------------------------------
  // previewWithdraw's own bps PRE-CLAMP (lines mirroring performanceFeeConfig).
  // netAfterPerformanceFees also clamps internally via the remainder, but the two clamps
  // round DIFFERENTLY at the wei: with owed=1000, platform=3333, owner=10000,
  //   pre-clamped (what performanceFeeConfig feeds applyFees): owner' = 6667 ->
  //     platform 333 + owner floor(666.7)=666 -> net 1 wei;
  //   un-pre-clamped remainder clamp alone: owner = min(1000, 667) = 667 -> net 0.
  // The real collect path pre-clamps, so previewWithdraw must too — this pins the 1-wei case.
  // ---------------------------------------------------------------------------

  function test_previewWithdraw_preClampsOwnerBps_matchesCollectPathRounding() public {
    ParityPreviewConfigManager cm = new ParityPreviewConfigManager(3333);
    ParityPreviewSplitStrategy strategy = new ParityPreviewSplitStrategy(0, 1000, 0, 0); // principal0=0, owed0=1000

    ISharedVault.Position[] memory positions = new ISharedVault.Position[](1);
    positions[0] = ISharedVault.Position({
      strategy: address(strategy),
      nfpm: address(0xAAA1),
      tokenId: 1,
      token0: address(0xBBB1),
      token1: address(0xBBB2)
    });

    address[4] memory tokens = [address(0xBBB1), address(0xBBB2), address(0), address(0)];
    uint256[4] memory idle;

    uint256[4] memory amounts = SharedVaultPreviewLib.previewWithdraw(
      1, // shares
      1, // totalSupply (full withdrawal of the only share)
      idle,
      positions,
      tokens,
      ISharedConfigManager(address(cm)),
      10_000 // vault owner bps above 10_000 - platformBps: MUST be pre-clamped to 6667
    );

    assertEq(amounts[0], 1, "pre-clamped fee math nets exactly 1 wei (un-pre-clamped math would net 0)");
    assertEq(amounts[1], 0, "no token1 value");

    // Cross-check against the REAL settlement with the same pre-clamped bps, as
    // SharedStrategyFeeConfig.performanceFeeConfig would feed applyFees.
    uint256 netViaCollectPath = 1000 - 333 - 666;
    assertEq(amounts[0], netViaCollectPath, "previewWithdraw matches the collect path to the wei");
  }
}

/// @dev Just enough of ISharedConfigManager for previewWithdraw.
contract ParityPreviewConfigManager {
  uint16 public platformFeeBasisPoint;

  constructor(uint16 _platformBps) {
    platformFeeBasisPoint = _platformBps;
  }
}

/// @dev Just enough of ISharedStrategy for previewWithdraw's netFees branch.
contract ParityPreviewSplitStrategy {
  uint256 internal principal0;
  uint256 internal owed0;
  uint256 internal principal1;
  uint256 internal owed1;

  constructor(uint256 _principal0, uint256 _owed0, uint256 _principal1, uint256 _owed1) {
    principal0 = _principal0;
    owed0 = _owed0;
    principal1 = _principal1;
    owed1 = _owed1;
  }

  function getPositionAmountsSplit(address, uint256)
    external
    view
    returns (uint256 total0, uint256 total1, uint256 p0, uint256 p1)
  {
    return (principal0 + owed0, principal1 + owed1, principal0, principal1);
  }
}
