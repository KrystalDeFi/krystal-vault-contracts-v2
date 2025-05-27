pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Token is ERC20 {
  // Decimals are set to 18 by default in `ERC20`
  constructor() ERC20("MockERC20Token", "TOKEN") {
    _mint(msg.sender, type(uint256).max);
  }
}
