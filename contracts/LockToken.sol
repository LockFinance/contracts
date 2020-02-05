pragma solidity 0.5.15;

import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';

contract LockToken is ERC20 {

    uint public totalTokensAmount = 1000000000;

    string public name = "Lock Token";
    string public symbol = "LOCK";
    uint8 public decimals = 18;


    constructor() public {
        // mint totalTokensAmount times 10^decimals for operator
        _mint(msg.sender, totalTokensAmount  * (10 ** uint256(decimals)));
    }
}