
# Lock finance audit report.

# 1. Summary

This document is a security audit report performed by [danbogd](https://github.com/danbogd), where [lock.finance](https://github.com/LockFinance/contracts/blob/master/contracts/Lock.sol) has been reviewed.

# 2. In scope

Сommit hash 1e7210d84746d58447939440daf5de959a82666c.

- [Lock.sol](https://github.com/LockFinance/contracts/blob/1e7210d84746d58447939440daf5de959a82666c/contracts/Lock.sol).


# 3. Findings

In total, **4 issues** were reported including:

 - 0 high severity issues
 - 1 medium severity issues
 - 1 low severity issues
 - 1 owner privileges (ability of owner to manipulate contract, may be risky for investors).
 - 1 notes.

No critical security issues were found.

## 3.1. There is no way to remove outdated airdrops
### Severity: medium
### Description

At each claim of funds there is a calculation of airdrops. This occurs in a loop and can cause the throw of transaction if array of airdrops will be huge. In case of Ethereum an amount of airdrops can be really huge. But there is no way in this contract to remove outdated airdrops from array to prevent this. This can lead to the blocking of funds without the ability to return them.

### Code snippet

https://github.com/LockFinance/contracts/blob/1e7210d84746d58447939440daf5de959a82666c/contracts/Lock.sol#L816-L839


```js
        function _claimAirdroppedTokens(
        address baseToken,
        uint256 lockDate,
        uint256 amount
    )
        private
    {
        //This loop can be very costly if number of airdropped tokens
        //for base token is very large. But we assume that it is not going to be the case
        for(uint256 i = 0; i < _baseTokenVsAirdrops[baseToken].length; i++) {

            Airdrop memory airdrop = _baseTokenVsAirdrops[baseToken][i];

            if(airdrop.date < lockDate || airdrop.date > block.timestamp) {
                return;
            }
            else {
                uint256 airdropAmount = amount.mul(airdrop.numerator).div(airdrop.denominator);
                IERC20(airdrop.destToken).safeTransfer(msg.sender, airdropAmount);
                emit TokensAirdropped(airdrop.destToken, airdropAmount);
            }
        }

    }
```
### Recommendation

Add the mechanism that allows to remove outdated airdrops from the mapping `_baseTokenVsAirdrops`.


## 3.2. Owner Privileges

### Severity: owner previliges

### Description


- The owner can set any value of fee up to 100%.

```js

        function setFee(uint256 fee) external onlyOwner {
        _fee = fee;
        emit FeeChanged(fee);
    }
```

### Code snippet

https://github.com/LockFinance/contracts/blob/1e7210d84746d58447939440daf5de959a82666c/contracts/Lock.sol#L479

### Recomendation

I think that this owner previliges may be justified. About another owner actions as Emergency unlock of a token and manage token airdrops for any asset the client can get information from the official site [https://docs.lock.finance/](https://docs.lock.finance) under the section Administration.


## 3.3. Payable function without withdraw
### Severity: low
### Description

`lock()` function allows to deposit Ether to the contract, but there is no way to withdraw these funds. In case if using lock of tokens but accidently sends ether is possible loss of funds.

### Code snippet

https://github.com/LockFinance/contracts/blob/1e7210d84746d58447939440daf5de959a82666c/contracts/Lock.sol#L605-L660


## 3.4. It is required to limit the maximum of date argument.

### Severity: note

### Description

For various reasons (accident), `date` or `duration` variable may have a large value which can lead to blocking tokens for many many years. We can not rely on the correct input data and should check it in this contract.

```js
        function lock(
        address tokenAddress,
        uint256 amount,
        uint256 duration,
        address payable beneficiary
    )
        external
        payable
        whenNotPaused
        canLockAsset(tokenAddress)
    {
        require(
            beneficiary != address(0),
            "Lock: Provide valid beneficiary address!!"
        );

        Token memory token = _tokens[_tokenVsIndex[tokenAddress].sub(1)];

        require(
            amount >= token.minAmount,
            "Lock: Please provide minimum amount of tokens!!"
        );

        uint256 endDate = block.timestamp.add(duration);
        uint256 fee = amount.mul(_fee).div(10000);
        uint256 newAmount = amount.sub(fee);

        if(ETH_ADDRESS == tokenAddress) {
            _lockETH(
                newAmount,
                fee,
                endDate,
                beneficiary
            );
        }

        else {
            _lockERC20(
                tokenAddress,
                newAmount,
                fee,
                endDate,
                beneficiary
            );
        }

        emit AssetLocked(
            tokenAddress,
            msg.sender,
            beneficiary,
            _lockId,
            newAmount,
            block.timestamp,
            endDate
        );
    } 
        
```

```js
        function setAirdrop(
        address baseToken,
        address destToken,
        uint256 numerator,
        uint256 denominator,
        uint256 date
    )
        external
        onlyOwner
        tokenExist(baseToken)
    {
        require(destToken != address(0), "Lock: Invalid destination token!!");
        require(numerator > 0, "Lock: Invalid numerator!!");
        require(denominator > 0, "Lock: Invalid denominator!!");
        require(isActive(baseToken), "Lock: Base token is not active!!");

        _baseTokenVsAirdrops[baseToken].push(Airdrop({
            destToken: destToken,
            numerator: numerator,
            denominator: denominator,
            date: date
        }));

        emit AirdropAdded(
            baseToken,
            destToken,
            date
        );
    }
```
### Code snippet

https://github.com/LockFinance/contracts/blob/1e7210d84746d58447939440daf5de959a82666c/contracts/Lock.sol#L413-L441

https://github.com/LockFinance/contracts/blob/1e7210d84746d58447939440daf5de959a82666c/contracts/Lock.sol#L605-L660


## 4. Conclusion

The review did not show any critical issues, some of medium and low severity issues were found.


