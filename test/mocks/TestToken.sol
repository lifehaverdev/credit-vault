// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "solady/tokens/ERC20.sol";

contract TestToken is ERC20 {
    constructor() {
        _mint(msg.sender, 1_000_000e18);
    }

    function name() public pure override returns (string memory) {
        return "MockToken";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCK";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
