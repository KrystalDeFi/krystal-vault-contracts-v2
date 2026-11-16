// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Plain ERC-20 (OpenZeppelin semantics: allowances are enforced on transferFrom) with a public mint.
contract FaithfulERC20 is ERC20 {
  uint8 private immutable _decimals;

  constructor(string memory symbol, uint8 decimals_) ERC20(symbol, symbol) {
    _decimals = decimals_;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function mint(address to, uint256 amount) external virtual {
    _mint(to, amount);
  }
}

/// @dev WETH9 semantics: deposit mints 1:1 for msg.value, withdraw burns and pays out with a 2300-gas transfer.
contract FaithfulWETH9 is FaithfulERC20 {
  constructor() FaithfulERC20("WETH", 18) { }

  /// @dev WETH9 has no mint: every token is backed by deposited ETH.
  function mint(address, uint256) external pure override {
    revert("WETH: use deposit");
  }

  function deposit() public payable {
    _mint(msg.sender, msg.value);
  }

  function withdraw(uint256 wad) external {
    _burn(msg.sender, wad);
    payable(msg.sender).transfer(wad);
  }

  receive() external payable {
    deposit();
  }
}

/// @dev Permit2 AllowanceTransfer subset used by the V4 / Infinity position managers to pull settlements
///      (permit2/src/AllowanceTransfer.sol: `approve`, `transferFrom`; permit2/src/libraries/Allowance.sol:
///      `updateAmountAndExpiration`, where expiration 0 means "the current block").
contract FaithfulPermit2 {
  using SafeERC20 for IERC20;

  error AllowanceExpired(uint256 deadline);
  error InsufficientAllowance(uint256 amount);

  struct PackedAllowance {
    uint160 amount;
    uint48 expiration;
    uint48 nonce;
  }

  mapping(address owner => mapping(address token => mapping(address spender => PackedAllowance))) public allowance;

  function approve(address token, address spender, uint160 amount, uint48 expiration) external {
    PackedAllowance storage allowed = allowance[msg.sender][token][spender];
    allowed.amount = amount;
    allowed.expiration = expiration == 0 ? uint48(block.timestamp) : expiration;
  }

  /// @dev AllowanceTransfer._transfer: expiry checked first, then the amount (type(uint160).max never decrements),
  ///      then the ERC-20 pull, which needs the owner's ERC-20 allowance to Permit2 itself.
  function transferFrom(address from, address to, uint160 amount, address token) external {
    PackedAllowance storage allowed = allowance[from][token][msg.sender];
    if (block.timestamp > allowed.expiration) revert AllowanceExpired(allowed.expiration);
    uint256 maxAmount = allowed.amount;
    if (maxAmount != type(uint160).max) {
      if (amount > maxAmount) revert InsufficientAllowance(maxAmount);
      unchecked {
        allowed.amount = uint160(maxAmount) - amount;
      }
    }
    IERC20(token).safeTransferFrom(from, to, amount);
  }
}
