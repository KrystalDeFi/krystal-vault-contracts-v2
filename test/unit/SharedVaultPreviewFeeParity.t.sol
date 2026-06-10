// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
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
}
