// SPDX-License-Identifier: MIT

// ERC20 Implementation

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";

contract Token is ERC20 {

    constructor(uint256 initialSupply, string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }

}
