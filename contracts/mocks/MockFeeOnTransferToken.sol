// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test token that burns a percentage on every transfer. NOT for production.
contract MockFeeOnTransferToken is ERC20 {
    uint256 public immutable burnBps;

    constructor(uint256 burnBps_) ERC20("FeeToken", "FEE") {
        burnBps = burnBps_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 burned = (value * burnBps) / 10_000;
            super._update(from, address(0), burned);
            super._update(from, to, value - burned);
        } else {
            super._update(from, to, value);
        }
    }
}
