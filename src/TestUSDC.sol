// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestUSDC is ERC20, Ownable {
    constructor() ERC20("Test USDC", "tUSDC") Ownable(msg.sender) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Allows the owner to create new tokens.
     * @param to The address that will receive the tokens.
     * @param amount The amount of tokens to mint (in the smallest unit).
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
