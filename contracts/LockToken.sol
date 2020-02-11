pragma solidity 0.5.15;

import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';


contract LockToken is ERC20, Ownable {

    uint public initialSupply = 1000;

    string public name = "Lock Protocol Token";
    string public symbol = "LOCK";
    uint8 public decimals = 18;


    constructor() public {
        // mint totalTokensAmount times 10^decimals for operator
        _mint(msg.sender, initialSupply  * (10 ** uint256(decimals)));
    }

    /**
     * @dev See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the owner.
     */
    function mint(
        address account,
        uint256 amount
    )
        external
        onlyOwner
        returns(bool)
    {
        _mint(account, amount);
        return true;
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     * Only owner should call this function
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev See {ERC20-_burnFrom}.
     * Only owner should call this function
     */
    function burnFrom(address account, uint256 amount) external onlyOwner {
        _burnFrom(account, amount);
    }
}