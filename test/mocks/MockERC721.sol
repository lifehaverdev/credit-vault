// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";

contract MockERC721 is ERC721 {
    string private _name;
    string private _symbol;

    constructor() {
        _name   = 'name';
        _symbol = 'TEST';
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function mint(address to, uint256 id) external {
        _safeMint(to, id);
    }
}
