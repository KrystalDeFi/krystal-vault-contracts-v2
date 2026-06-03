// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedV4StrategyLib.sol";
import { SharedPancakeV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedPancakeV4StrategyLib.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";

/// @dev Harness exposing the internal selector/body helpers of `SharedV4StrategyLib`. The helper is
///      called INLINE inside the harness's own call frame, so any in-place mutation of `params`
///      lands on this frame's buffer and is observable via the returned length/selector — an
///      external call would deep-copy `params` and hide a mutation bug.
contract V4ParamsHarness {
  function bodyAndProbe(bytes memory params)
    external
    pure
    returns (bytes memory strippedBody, uint256 lenAfter, bytes4 selectorAfter)
  {
    strippedBody = SharedV4StrategyLib._v4ParamsBody(params);
    lenAfter = params.length;
    selectorAfter = bytes4(params);
  }

  function body(bytes memory params) external pure returns (bytes memory) {
    return SharedV4StrategyLib._v4ParamsBody(params);
  }

  function selector(bytes memory params) external pure returns (bytes4) {
    return SharedV4StrategyLib._v4ParamsSelector(params);
  }
}

contract PancakeV4ParamsHarness {
  function bodyAndProbe(bytes memory params)
    external
    pure
    returns (bytes memory strippedBody, uint256 lenAfter, bytes4 selectorAfter)
  {
    strippedBody = SharedPancakeV4StrategyLib._v4ParamsBody(params);
    lenAfter = params.length;
    selectorAfter = bytes4(params);
  }

  function body(bytes memory params) external pure returns (bytes memory) {
    return SharedPancakeV4StrategyLib._v4ParamsBody(params);
  }

  function selector(bytes memory params) external pure returns (bytes4) {
    return SharedPancakeV4StrategyLib._v4ParamsSelector(params);
  }
}

/// @notice Regression + correctness tests for the `_v4ParamsBody` / `_v4ParamsSelector` calldata
///         strippers shared by the V4 and PancakeV4 strategy libraries.
/// @dev The non-mutation tests below FAIL against the historical in-place implementation
///      (`body := add(params, 4); mstore(body, mload(params) - 4)`), which clobbered the caller's
///      length word and selector. They pass only when `_v4ParamsBody` builds a fresh buffer.
contract SharedV4ParamsDecodeTest is Test {
  V4ParamsHarness internal v4;
  PancakeV4ParamsHarness internal pancake;

  bytes4 internal constant SEL = bytes4(0x12345678);

  function setUp() public {
    v4 = new V4ParamsHarness();
    pancake = new PancakeV4ParamsHarness();
  }

  // --------------------------------------------------------------------------------------------
  // Non-mutation regression guard
  // --------------------------------------------------------------------------------------------

  function _assertNoMutation(bytes memory bodyContent) internal view {
    bytes memory params = abi.encodePacked(SEL, bodyContent);
    uint256 origLen = params.length;
    bytes4 origSel = bytes4(params);

    (bytes memory v4Body, uint256 v4Len, bytes4 v4Sel) = v4.bodyAndProbe(params);
    assertEq(v4Body, bodyContent, "v4: body mismatch");
    assertEq(v4Len, origLen, "v4: params length mutated");
    assertTrue(v4Sel == origSel, "v4: selector mutated");

    (bytes memory pBody, uint256 pLen, bytes4 pSel) = pancake.bodyAndProbe(params);
    assertEq(pBody, bodyContent, "pancake: body mismatch");
    assertEq(pLen, origLen, "pancake: params length mutated");
    assertTrue(pSel == origSel, "pancake: selector mutated");
  }

  function test_v4ParamsBody_doesNotMutateInput_wordAligned() public view {
    _assertNoMutation(abi.encode(uint256(0xdead), address(0xBEEF), uint256(42)));
  }

  function test_v4ParamsBody_doesNotMutateInput_unaligned() public view {
    // 13-byte tail: exercises the non-word-multiple copy length (mcopy must not over-write).
    _assertNoMutation(hex"00112233445566778899aabbcc");
  }

  function test_v4ParamsBody_doesNotMutateInput_emptyBody() public view {
    // params is exactly the 4-byte selector; body must be empty and input untouched.
    _assertNoMutation(hex"");
  }

  function test_v4ParamsBody_doesNotMutateInput_largeBody() public view {
    bytes memory big = new bytes(1024);
    for (uint256 i; i < big.length; ++i) {
      big[i] = bytes1(uint8(i % 251));
    }
    _assertNoMutation(big);
  }

  function testFuzz_v4ParamsBody_doesNotMutateInput(bytes memory bodyContent) public view {
    _assertNoMutation(bodyContent);
  }

  // --------------------------------------------------------------------------------------------
  // Functional correctness: round-trip ABI decode through the stripped body
  // --------------------------------------------------------------------------------------------

  function test_v4ParamsBody_roundTripDecode() public view {
    address addr = address(0xCAFE);
    uint256 num = 123_456;
    bytes memory blob = hex"deadbeefcafe";
    bytes memory params = abi.encodeWithSelector(SEL, addr, num, blob);

    (address dAddr, uint256 dNum, bytes memory dBlob) = abi.decode(v4.body(params), (address, uint256, bytes));
    assertEq(dAddr, addr, "addr");
    assertEq(dNum, num, "num");
    assertEq(dBlob, blob, "blob");

    (address pAddr, uint256 pNum, bytes memory pBlob) = abi.decode(pancake.body(params), (address, uint256, bytes));
    assertEq(pAddr, addr, "p addr");
    assertEq(pNum, num, "p num");
    assertEq(pBlob, blob, "p blob");
  }

  function test_v4ParamsSelector_returnsLeading4Bytes() public view {
    bytes memory params = abi.encodePacked(SEL, abi.encode(uint256(7)));
    assertTrue(v4.selector(params) == SEL, "v4 selector");
    assertTrue(pancake.selector(params) == SEL, "pancake selector");
  }

  // --------------------------------------------------------------------------------------------
  // Guard: too-short input reverts
  // --------------------------------------------------------------------------------------------

  function test_v4ParamsBody_revertsWhenShorterThan4Bytes() public {
    bytes memory tooShort = hex"001122"; // 3 bytes
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    v4.body(tooShort);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    pancake.body(tooShort);
  }

  function test_v4ParamsSelector_revertsWhenShorterThan4Bytes() public {
    bytes memory tooShort = hex"0011"; // 2 bytes
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    v4.selector(tooShort);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    pancake.selector(tooShort);
  }
}
