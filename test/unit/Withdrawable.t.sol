// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { Withdrawable } from "../../contracts/common/Withdrawable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// Mock contract that extends Withdrawable for testing
contract MockWithdrawable is Ownable, Withdrawable {
  constructor(address owner) Ownable(owner) { }

  function _checkWithdrawPermission() internal view override {
    _checkOwner();
  }

  // Allow receiving native tokens
  receive() external payable { }
}

// Mock ERC20 token for testing
contract MockERC20 {
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    allowance[from][msg.sender] -= amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// Mock ERC721 token for testing
contract MockERC721 {
  mapping(uint256 => address) private _owners;
  mapping(address => uint256) public balanceOf;

  function mint(address to, uint256 tokenId) external {
    require(_owners[tokenId] == address(0), "Token already minted");
    _owners[tokenId] = to;
    balanceOf[to]++;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    address owner = _owners[tokenId];
    require(owner != address(0), "Token does not exist");
    return owner;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(_owners[tokenId] == from, "Not the owner");
    _owners[tokenId] = to;
    balanceOf[from]--;
    balanceOf[to]++;
  }

  function approve(address, uint256) external pure returns (bool) {
    return true;
  }

  function getApproved(uint256) external pure returns (address) {
    return address(0);
  }

  function setApprovalForAll(address, bool) external pure { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}

// Mock ERC1155 token for testing
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 tokenId, uint256 amount) external {
    balanceOf[to][tokenId] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes calldata) external {
    require(balanceOf[from][tokenId] >= amount, "Insufficient balance");
    balanceOf[from][tokenId] -= amount;
    balanceOf[to][tokenId] += amount;
  }

  function setApprovalForAll(address, bool) external pure { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}

contract WithdrawableTest is TestCommon {
  MockWithdrawable public withdrawable;
  MockERC20 public mockERC20;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;

  address public constant OWNER = address(0x1);
  address public constant NON_OWNER = address(0x2);

  function setUp() public {
    withdrawable = new MockWithdrawable(OWNER);
    mockERC20 = new MockERC20();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();
  }

  // ========== sweepNativeToken Tests ==========

  function test_sweepNativeToken_success() public {
    uint256 amount = 1 ether;
    vm.deal(address(withdrawable), amount);

    uint256 ownerBalanceBefore = OWNER.balance;

    vm.prank(OWNER);
    withdrawable.sweepNativeToken(amount);

    assertEq(OWNER.balance, ownerBalanceBefore + amount);
    assertEq(address(withdrawable).balance, 0);
  }

  function test_sweepNativeToken_partial_amount() public {
    uint256 factoryBalance = 0.5 ether;
    uint256 sweepAmount = 1 ether; // More than balance

    vm.deal(address(withdrawable), factoryBalance);

    uint256 ownerBalanceBefore = OWNER.balance;

    vm.prank(OWNER);
    withdrawable.sweepNativeToken(sweepAmount);

    // Should sweep only the available balance
    assertEq(OWNER.balance, ownerBalanceBefore + factoryBalance);
    assertEq(address(withdrawable).balance, 0);
  }

  function test_sweepNativeToken_unauthorized() public {
    uint256 amount = 1 ether;
    vm.deal(address(withdrawable), amount);

    vm.prank(NON_OWNER);
    vm.expectRevert();
    withdrawable.sweepNativeToken(amount);
  }

  // ========== sweepERC20 Tests ==========

  function test_sweepERC20_success() public {
    uint256 amount = 1000;

    // Mint tokens to withdrawable
    mockERC20.mint(address(withdrawable), amount);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(OWNER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(OWNER);
    withdrawable.sweepERC20(tokens, amounts);

    assertEq(mockERC20.balanceOf(OWNER), ownerBalanceBefore + amount);
    assertEq(mockERC20.balanceOf(address(withdrawable)), 0);
  }

  function test_sweepERC20_multiple_tokens() public {
    MockERC20 mockERC20_2 = new MockERC20();
    uint256 amount1 = 1000;
    uint256 amount2 = 2000;

    // Mint tokens to withdrawable
    mockERC20.mint(address(withdrawable), amount1);
    mockERC20_2.mint(address(withdrawable), amount2);

    uint256 ownerBalanceBefore1 = mockERC20.balanceOf(OWNER);
    uint256 ownerBalanceBefore2 = mockERC20_2.balanceOf(OWNER);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC20);
    tokens[1] = address(mockERC20_2);
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.prank(OWNER);
    withdrawable.sweepERC20(tokens, amounts);

    assertEq(mockERC20.balanceOf(OWNER), ownerBalanceBefore1 + amount1);
    assertEq(mockERC20_2.balanceOf(OWNER), ownerBalanceBefore2 + amount2);
    assertEq(mockERC20.balanceOf(address(withdrawable)), 0);
    assertEq(mockERC20_2.balanceOf(address(withdrawable)), 0);
  }

  function test_sweepERC20_partial_amount() public {
    uint256 factoryBalance = 500;
    uint256 sweepAmount = 1000; // More than balance

    // Mint tokens to withdrawable
    mockERC20.mint(address(withdrawable), factoryBalance);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(OWNER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = sweepAmount;

    vm.prank(OWNER);
    withdrawable.sweepERC20(tokens, amounts);

    // Should sweep only the available balance
    assertEq(mockERC20.balanceOf(OWNER), ownerBalanceBefore + factoryBalance);
    assertEq(mockERC20.balanceOf(address(withdrawable)), 0);
  }

  function test_sweepERC20_zero_token() public {
    uint256 amount = 1000;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(OWNER);
    vm.expectRevert("ZeroAddress");
    withdrawable.sweepERC20(tokens, amounts);
  }

  function test_sweepERC20_unauthorized() public {
    uint256 amount = 1000;
    mockERC20.mint(address(withdrawable), amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(NON_OWNER);
    vm.expectRevert();
    withdrawable.sweepERC20(tokens, amounts);
  }

  function test_sweepERC20_array_length_mismatch() public {
    uint256 amount = 1000;
    mockERC20.mint(address(withdrawable), amount);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC20);
    tokens[1] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(OWNER);
    vm.expectRevert(Withdrawable.ArrayLengthMismatch.selector);
    withdrawable.sweepERC20(tokens, amounts);
  }

  // ========== sweepERC721 Tests ==========

  function test_sweepERC721_success() public {
    uint256 tokenId = 1;

    // Mint NFT to withdrawable
    mockERC721.mint(address(withdrawable), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(OWNER);
    withdrawable.sweepERC721(tokens, tokenIds);

    assertEq(mockERC721.ownerOf(tokenId), OWNER);
    assertEq(mockERC721.balanceOf(address(withdrawable)), 0);
  }

  function test_sweepERC721_multiple_tokens() public {
    uint256 tokenId1 = 1;
    uint256 tokenId2 = 2;

    // Mint NFTs to withdrawable
    mockERC721.mint(address(withdrawable), tokenId1);
    mockERC721.mint(address(withdrawable), tokenId2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC721);
    tokens[1] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;

    vm.prank(OWNER);
    withdrawable.sweepERC721(tokens, tokenIds);

    assertEq(mockERC721.ownerOf(tokenId1), OWNER);
    assertEq(mockERC721.ownerOf(tokenId2), OWNER);
    assertEq(mockERC721.balanceOf(address(withdrawable)), 0);
  }

  function test_sweepERC721_zero_token() public {
    uint256 tokenId = 1;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(OWNER);
    vm.expectRevert("ZeroAddress");
    withdrawable.sweepERC721(tokens, tokenIds);
  }

  function test_sweepERC721_unauthorized() public {
    uint256 tokenId = 1;
    mockERC721.mint(address(withdrawable), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(NON_OWNER);
    vm.expectRevert();
    withdrawable.sweepERC721(tokens, tokenIds);
  }

  function test_sweepERC721_array_length_mismatch() public {
    uint256 tokenId = 1;
    mockERC721.mint(address(withdrawable), tokenId);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC721);
    tokens[1] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(OWNER);
    vm.expectRevert(Withdrawable.ArrayLengthMismatch.selector);
    withdrawable.sweepERC721(tokens, tokenIds);
  }

  // ========== sweepERC1155 Tests ==========

  function test_sweepERC1155_success() public {
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint ERC1155 tokens to withdrawable
    mockERC1155.mint(address(withdrawable), tokenId, amount);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(OWNER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(OWNER);
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(mockERC1155.balanceOf(OWNER, tokenId), ownerBalanceBefore + amount);
    assertEq(mockERC1155.balanceOf(address(withdrawable), tokenId), 0);
  }

  function test_sweepERC1155_multiple_tokens() public {
    MockERC1155 mockERC1155_2 = new MockERC1155();
    uint256 tokenId1 = 1;
    uint256 tokenId2 = 2;
    uint256 amount1 = 100;
    uint256 amount2 = 200;

    // Mint ERC1155 tokens to withdrawable
    mockERC1155.mint(address(withdrawable), tokenId1, amount1);
    mockERC1155_2.mint(address(withdrawable), tokenId2, amount2);

    uint256 ownerBalanceBefore1 = mockERC1155.balanceOf(OWNER, tokenId1);
    uint256 ownerBalanceBefore2 = mockERC1155_2.balanceOf(OWNER, tokenId2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC1155);
    tokens[1] = address(mockERC1155_2);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.prank(OWNER);
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(mockERC1155.balanceOf(OWNER, tokenId1), ownerBalanceBefore1 + amount1);
    assertEq(mockERC1155_2.balanceOf(OWNER, tokenId2), ownerBalanceBefore2 + amount2);
    assertEq(mockERC1155.balanceOf(address(withdrawable), tokenId1), 0);
    assertEq(mockERC1155_2.balanceOf(address(withdrawable), tokenId2), 0);
  }

  function test_sweepERC1155_partial_amount() public {
    uint256 tokenId = 1;
    uint256 factoryBalance = 50;
    uint256 sweepAmount = 100; // More than balance

    // Mint ERC1155 tokens to withdrawable
    mockERC1155.mint(address(withdrawable), tokenId, factoryBalance);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(OWNER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = sweepAmount;

    vm.prank(OWNER);
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);

    // Should sweep only the available balance
    assertEq(mockERC1155.balanceOf(OWNER, tokenId), ownerBalanceBefore + factoryBalance);
    assertEq(mockERC1155.balanceOf(address(withdrawable), tokenId), 0);
  }

  function test_sweepERC1155_zero_token() public {
    uint256 tokenId = 1;
    uint256 amount = 100;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(OWNER);
    vm.expectRevert("ZeroAddress");
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);
  }

  function test_sweepERC1155_unauthorized() public {
    uint256 tokenId = 1;
    uint256 amount = 100;
    mockERC1155.mint(address(withdrawable), tokenId, amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(NON_OWNER);
    vm.expectRevert();
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);
  }

  function test_sweepERC1155_array_length_mismatch_tokens_tokenIds() public {
    uint256 tokenId = 1;
    uint256 amount = 100;
    mockERC1155.mint(address(withdrawable), tokenId, amount);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC1155);
    tokens[1] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount;
    amounts[1] = amount;

    vm.prank(OWNER);
    vm.expectRevert(Withdrawable.ArrayLengthMismatch.selector);
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);
  }

  function test_sweepERC1155_array_length_mismatch_tokens_amounts() public {
    uint256 tokenId = 1;
    uint256 amount = 100;
    mockERC1155.mint(address(withdrawable), tokenId, amount);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC1155);
    tokens[1] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId;
    tokenIds[1] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(OWNER);
    vm.expectRevert(Withdrawable.ArrayLengthMismatch.selector);
    withdrawable.sweepERC1155(tokens, tokenIds, amounts);
  }
}
