// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Emma is ERC20, Ownable {
    constructor(address recipient, address initialOwner) ERC20("emma", "MTK") Ownable(initialOwner) {
        _mint(recipient, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
