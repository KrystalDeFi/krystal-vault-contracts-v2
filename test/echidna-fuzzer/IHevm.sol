pragma solidity ^0.8.0;

interface IHevm {
    // https://hevm.dev/std-test-tutorial.html#supported-cheat-codes
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function deal(address usr, uint amt) external;
    function store(address c, bytes32 loc, bytes32 val) external;
    function warp(uint x) external;
    function roll(uint x) external;
    function assume(bool b) external;
    function load(address c, bytes32 loc) external returns (bytes32 val);
    function sign(uint sk, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function addr(uint sk) external returns (address addr);
    function ffi(string[] calldata) external returns (bytes memory);
    function createFork(string calldata urlOrAlias) external returns (uint256);
    function selectFork(uint256 forkId) external;
    function activeFork() external returns (uint256);
    function label(address addr, string calldata label) external;
} 
