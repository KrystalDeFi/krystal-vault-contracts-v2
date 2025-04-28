pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IHevm {
    function warp(uint256 newTimestamp) external;

    function roll(uint256 newNumber) external;
}

interface Compound {
    function mint() external payable;

    function balanceOf(address) external view returns (uint256);
}

contract TestCompoundEthMint {    

    address constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    IHevm hevm = IHevm(HEVM_ADDRESS);
    // Compound comp = Compound(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

    constructor() {
        // hevm.roll(22365182);
        // hevm.warp(1678131671);
    }

    // function assertNoBalance() public payable {
    //     require(comp.balanceOf(address(this)) == 0);
    //     comp.mint{ value: msg.value }();
    //     assert(comp.balanceOf(address(this)) == 0);
    // }

    function assertEthBalance() public {
        // assert( block.number == 16771449);
        assert(address(0xF51D0C3D466b1B0A763031970276047B4a9338E5).balance == 0);
    }

    function assertUSDCBalance() public {
        assert(IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).balanceOf(address(0xF51D0C3D466b1B0A763031970276047B4a9338E5)) == 0);
    }
}
