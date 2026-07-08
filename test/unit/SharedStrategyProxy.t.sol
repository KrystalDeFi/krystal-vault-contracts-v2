// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedStrategyBeacon } from "../../contracts/shared-vault/strategies/SharedStrategyBeacon.sol";
import { SharedStrategyProxy } from "../../contracts/shared-vault/strategies/SharedStrategyProxy.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { Withdrawable } from "../../contracts/common/Withdrawable.sol";

// ─── Mock implementations ──────────────────────────────────────────────────

/// @dev Simple stateful mock. When the proxy delegates here, reads/writes hit the proxy's
///      own storage (slot 0) — correct for direct (non-delegatecall) calls under test.
contract MockImplV1 {
  uint256 public value;

  error MockError(uint256 code);

  function getValue() external view returns (uint256) {
    return value;
  }

  function setValue(uint256 v) external {
    value = v;
  }

  function revertWithError(uint256 code) external pure {
    revert MockError(code);
  }

  function returnMultiple() external pure returns (uint256 a, address b, bool c) {
    return (42, address(0xdead), true);
  }
}

/// @dev V2 doubles the stored value — verifies that beacon upgrade takes effect immediately.
contract MockImplV2 {
  uint256 public value;

  function setValue(uint256 v) external {
    value = v * 2;
  }

  function getValue() external view returns (uint256) {
    return value;
  }
}

/// @dev Minimal ERC20 for sweep tests.
contract MockERC20Sweep {
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

/// @dev Minimal ERC721 for sweep tests.
contract MockERC721Sweep {
  mapping(uint256 => address) private _owners;

  function mint(address to, uint256 tokenId) external {
    _owners[tokenId] = to;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    return _owners[tokenId];
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(_owners[tokenId] == from, "Not owner");
    _owners[tokenId] = to;
  }
}

/// @dev Minimal ERC1155 for sweep tests.
contract MockERC1155Sweep {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 tokenId, uint256 amount) external {
    balanceOf[to][tokenId] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes calldata) external {
    require(balanceOf[from][tokenId] >= amount, "Insufficient");
    balanceOf[from][tokenId] -= amount;
    balanceOf[to][tokenId] += amount;
  }

  function setApprovalForAll(address, bool) external {}
  function isApprovedForAll(address, address) external pure returns (bool) { return false; }
}

/// @dev Cast-helper so tests can call mock functions through the proxy address.
interface IMockImpl {
  function getValue() external view returns (uint256);
  function setValue(uint256 v) external;
  function revertWithError(uint256 code) external;
  function returnMultiple() external view returns (uint256, address, bool);
}

// ─── Test contract ────────────────────────────────────────────────────────

contract SharedStrategyProxyTest is TestCommon {
  SharedStrategyBeacon public beacon;
  SharedStrategyProxy public proxy;
  MockImplV1 public implV1;
  MockImplV2 public implV2;

  address public constant OWNER = address(0x1);
  address public constant NON_OWNER = address(0x2);

  function setUp() public {
    implV1 = new MockImplV1();
    implV2 = new MockImplV2();

    beacon = new SharedStrategyBeacon(address(implV1), OWNER);
    proxy = new SharedStrategyProxy(address(beacon));
  }

  // ========== Constructor ==========

  function test_constructor_setsBeacon() public view {
    assertEq(address(proxy.beacon()), address(beacon));
  }

  function test_constructor_revertsOnZeroBeacon() public {
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    new SharedStrategyProxy(address(0));
  }

  // ========== Fallback — forwarding ==========

  function test_fallback_forwardsCallToImpl() public {
    IMockImpl(address(proxy)).setValue(99);
    assertEq(IMockImpl(address(proxy)).getValue(), 99);
  }

  function test_fallback_forwardsMultipleReturnValues() public view {
    (uint256 a, address b, bool c) = IMockImpl(address(proxy)).returnMultiple();
    assertEq(a, 42);
    assertEq(b, address(0xdead));
    assertTrue(c);
  }

  function test_fallback_propagatesRevertPayload() public {
    uint256 code = 77;
    vm.expectRevert(abi.encodeWithSelector(MockImplV1.MockError.selector, code));
    IMockImpl(address(proxy)).revertWithError(code);
  }

  // ========== Fallback — beacon upgrade ==========

  /// @dev After setImplementation the proxy immediately uses V2 logic (doubles input).
  function test_fallback_usesNewImplAfterBeaconUpgrade() public {
    IMockImpl(address(proxy)).setValue(5);
    assertEq(IMockImpl(address(proxy)).getValue(), 5);

    vm.prank(OWNER);
    beacon.setImplementation(address(implV2));

    // V2.setValue doubles: writing 7 stores 14
    IMockImpl(address(proxy)).setValue(7);
    assertEq(IMockImpl(address(proxy)).getValue(), 14);
  }

  /// @dev Slot 0 written by V1 is readable by V2 — storage layout is shared across upgrades.
  function test_fallback_newImplReadsExistingProxyStorage() public {
    IMockImpl(address(proxy)).setValue(100);

    vm.prank(OWNER);
    beacon.setImplementation(address(implV2));

    assertEq(IMockImpl(address(proxy)).getValue(), 100);
  }

  // ========== receive() ==========

  function test_receive_acceptsETH() public {
    vm.deal(address(this), 1 ether);
    (bool ok, ) = address(proxy).call{ value: 1 ether }("");
    assertTrue(ok);
    assertEq(address(proxy).balance, 1 ether);
  }

  // ========== sweepNativeToken — gated to beacon.owner() ==========

  function test_sweepNativeToken_byBeaconOwner() public {
    vm.deal(address(proxy), 1 ether);
    uint256 before = OWNER.balance;

    vm.prank(OWNER);
    proxy.sweepNativeToken(1 ether);

    assertEq(OWNER.balance, before + 1 ether);
    assertEq(address(proxy).balance, 0);
  }

  function test_sweepNativeToken_revertsForNonOwner() public {
    vm.deal(address(proxy), 1 ether);

    vm.prank(NON_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    proxy.sweepNativeToken(1 ether);
  }

  // ========== sweepERC20 — gated to beacon.owner() ==========

  function test_sweepERC20_byBeaconOwner() public {
    MockERC20Sweep token = new MockERC20Sweep();
    token.mint(address(proxy), 500);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 500;

    vm.prank(OWNER);
    proxy.sweepERC20(tokens, amounts);

    assertEq(token.balanceOf(OWNER), 500);
    assertEq(token.balanceOf(address(proxy)), 0);
  }

  function test_sweepERC20_revertsForNonOwner() public {
    MockERC20Sweep token = new MockERC20Sweep();
    token.mint(address(proxy), 500);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 500;

    vm.prank(NON_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    proxy.sweepERC20(tokens, amounts);
  }

  // ========== sweepERC721 — gated to beacon.owner() ==========

  function test_sweepERC721_byBeaconOwner() public {
    MockERC721Sweep nft = new MockERC721Sweep();
    nft.mint(address(proxy), 1);

    address[] memory tokens = new address[](1);
    tokens[0] = address(nft);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.prank(OWNER);
    proxy.sweepERC721(tokens, tokenIds);

    assertEq(nft.ownerOf(1), OWNER);
  }

  function test_sweepERC721_revertsForNonOwner() public {
    MockERC721Sweep nft = new MockERC721Sweep();
    nft.mint(address(proxy), 1);

    address[] memory tokens = new address[](1);
    tokens[0] = address(nft);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.prank(NON_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    proxy.sweepERC721(tokens, tokenIds);
  }

  // ========== sweepERC1155 — gated to beacon.owner() ==========

  function test_sweepERC1155_byBeaconOwner() public {
    MockERC1155Sweep token1155 = new MockERC1155Sweep();
    token1155.mint(address(proxy), 5, 100);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 5;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100;

    vm.prank(OWNER);
    proxy.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(token1155.balanceOf(OWNER, 5), 100);
    assertEq(token1155.balanceOf(address(proxy), 5), 0);
  }

  function test_sweepERC1155_revertsForNonOwner() public {
    MockERC1155Sweep token1155 = new MockERC1155Sweep();
    token1155.mint(address(proxy), 5, 100);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 5;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100;

    vm.prank(NON_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    proxy.sweepERC1155(tokens, tokenIds, amounts);
  }

  // ========== Permission tracks beacon ownership dynamically ==========

  /// @dev _checkWithdrawPermission reads beacon.owner() at call time — transfer takes effect immediately.
  function test_sweepPermission_followsBeaconOwnershipTransfer() public {
    address newOwner = address(0x3);
    vm.deal(address(proxy), 1 ether);

    vm.prank(OWNER);
    beacon.transferOwnership(newOwner);

    // Old owner can no longer sweep
    vm.prank(OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    proxy.sweepNativeToken(1 ether);

    // New owner can sweep immediately
    uint256 before = newOwner.balance;
    vm.prank(newOwner);
    proxy.sweepNativeToken(1 ether);
    assertEq(newOwner.balance, before + 1 ether);
  }
}
