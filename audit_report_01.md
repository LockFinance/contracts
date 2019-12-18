# Disclaimer

THE CONTENT OF THIS AUDIT REPORT IS PROVIDED &quot;AS IS&quot;, WITHOUT REPRESENTATIONS AND WARRANTIES OF ANY KIND.

THE AUTHOR AND HIS EMPLOYER DISCLAIM ANY LIABILITY FOR DAMAGE ARISING OUT OF, OR IN CONNECTION WITH, THIS AUDIT REPORT.

COPYRIGHT OF THIS REPORT REMAINS WITH THE AUTHOR.

# Introduction

## Purpose of this Report

Cryptonics Consulting has been engaged to perform an audit of smart contract for the Lock project ([https://lock.finance/](https://lock.finance/)).

The objectives of the audit are as follows:

1. Determine correct functioning of the contract, in accordance with the project specification.
2. Determine possible vulnerabilities, which could be exploited by an attacker.
3. Determine contract bugs, which might lead to unexpected behavior.
4. Analyze, whether best practices have been applied during development.
5. Make recommendations to improve code safety and readability.

This report represents the summary of the findings.

As with any code audit, there is a limit to which vulnerabilities can be found, and unexpected execution paths may still be possible. The author of this report does not guarantee complete coverage (see disclaimer).

## Codebase Submitted To The audit

The smart contract code has been provided by the developers in form of public GitHub repository:

[https://github.com/LockFinance/contracts](https://github.com/LockFinance/contracts)

The commit number reviewed for this audit was: 1e7210d84746d58447939440daf5de959a82666c

## Methodology

The audit has been performed in the following steps:

1. Gaining an understanding of the contract&#39;s intended purpose by reading the available documentation.
2. Automated scanning of the contract with static code analysis tools for security vulnerabilities and use of best practice guidelines.
3. Manual line by line analysis of the contracts source code for security vulnerabilities and use of best practice guidelines, including but not limited to:
  - Reentrancy analysis
  - Race condition analysis
  - Front-running issues and transaction order dependencies
  - Time dependencies
  - Under- / overflow issues
  - Function visibility Issues
  - Possible denial of service attacks
  - Storage Layout Vulnerabilities
4. Report preparation

# Smart Contract Overview

The submitted smart contract implements an asset vault, that allows smart Ether and ERC-20 tokens to be timelocked into the smart contract. It also provides airdrop facilities associated with locked assets.

The full functionality is documented on the project&#39;s website: [https://docs.lock.finance/](https://docs.lock.finance/).





# Summary of Findings

The contract provided for this audit is of very good quality.

Community audited code seems to have been reused whenever possible. A safe math library is used to prevent overflow and underflow issues.

No reentrancy attack vectors have been found and precautions have been taken to avoid transaction ordering issues.

The overall design of the contract ensures that the only external calls that are performed are to contracts (ERC-20 tokens) explicitly authorized by the contract owner.

Two minor issues have been noted (see below).

Gas usage is reasonable for this type of contract.



# Issues Encountered

## Critical Issues

No minor issues have been found.

## Major Issues

No major issues have been found.

## Minor Issues

### Use of Transfer() NOt Recommended Anymore

The contract uses the **transfer()** function to transfer ETH in several places. This used to be considered good practice, in order to avoid reentrancy vulnerabilities.

However, since the recent Istanbul protocol update, gas costs for certain operations have changed, meaning that the 2300 gas forwarded by transfer may not be sufficient for smart contract-based wallets to receive ETH. Using **transfer()** is therefore not recommended anymore, since it may cause transfers to revert, when smart contracts are involved.

Most best practice guidelines have recently been updated in light of this change. See:

[https://diligence.consensys.net/blog/2019/09/stop-using-soliditys-transfer-now/](https://diligence.consensys.net/blog/2019/09/stop-using-soliditys-transfer-now/)

[https://consensys.github.io/smart-contract-best-practices/recommendations/#avoid-transfer-and-send](https://consensys.github.io/smart-contract-best-practices/recommendations/#avoid-transfer-and-send)

It therefore recommended to replace the **transfer()** calls with **call.value()**.

Note: To implement this recommendation safely, all ETH transfers should be moved to after state changes have been performed, in order to guard against reentrancy vulnerabilities.

**UPDATE: The team has addressed this issue by replacing all transfer() calls with call.value().**

### AirDrop Arrays may Grow to Large and Cause Block Gas Limit Issues

The functions **getAirdrops()** and **\_claimAirdroppedTokens()** loop over airdrop arrays. Should these arrays grow too large, these transactions will revert because of the block gas limit.

This issue is mitigated by the fact that airdrops can only be added by the contract&#39;s owner and can therefore not be exploited for a DoS style attack. However, since there is no way to remove an airdrop, it would be impossible for the contract owner to fix the issue should the array grow too large accidentally.

For extra safety, an airdrop removal method should be considered.

**UPDATE: The team is aware of this issue and will ensure off-chain that these arrays don not grow too large, since there is no risk of malicious or accidental exploitation by a user.**



# Security Audit Breakdown

## Reentrancy and Race Conditions REsistance

### Description

Reentrancy vulnerabilities consist in unexpected behavior, if a function is called various times before execution has completed. This may happen when calls to external contracts are made.

The following function, which can be used to withdraw the total balance of the caller from a contract is an example of reentrancy vulnerability:

```
mapping(address => uint) private balances;  
	  
function payOut() {
  
	require(msg.sender.call.value(balances[msg.sender])());
	balances[msg.sender] = 0;
  
}  
```

The _call.value() _invocation causes contract external code to be executed. If the caller is another contract, this means that the contracts fallback method is executed. This may call _payOut() _again, before the balance is set to 0, thereby obtaining more funds than available.

### Audit Result

**No reentrancy issues have been found in the contract. However, care must be taken not to introduce reentrancy vulnerabilities when fixing the first minor issue reported above.**

## Under-/Overflow Protection

### Description

Balances are usually represented by unsigned integers, typically 256-bit numbers in Solidity. When unsigned integers overflow or underflow, their value changes dramatically. Let&#39;s look at the following example of a more common underflow (numbers shortened for readability):

 0x0003 - 0x0004 = 0xFFFF

It&#39;s easy to see the issue here. Subtracting 1 more than available balance causes an underflow. The resulting balance is now a large number.

Also note, that in integer arithmetic division is troublesome, due to rounding errors.

### Audit Result

**The contracts avoid overflow and underflow issues by employing a safe math library for all arithmetic operations.**

## Transaction Ordering Assumptions

### Description

Transactions enter a pool of unconfirmed transactions and maybe included in blocks by miners in any order, depending on the miner&#39;s transaction selection criteria, which is probably some algorithm aimed at achieving maximum earnings from transaction fees, but could be anything. Hence, the order of transactions being included can be completely different to the order in which they are generated. Therefore, contract code cannot make any assumptions on transaction order.

Apart from unexpected results in contract execution, there is a possible attack vector in this, as transactions are visible in the mempool and their execution can be predicted. This maybe an issue in trading, where delaying a transaction may be used for personal advantage by a rogue miner. In fact, simply being aware of certain transactions before they are executed can be used as advantage by anyone, not just miners.

### Audit Result

**Transactions are kept as simple as possible and care has been taken not to assume a specific order of invocation.**

## Timestamp Dependencies

### DEscription

Timestamps are generated by the miners. Therefore, no contract should rely on the block timestamp for critical operations, such as using it as a seed for random number generation. [Consensys](https://new.consensys.net/) give a 15 seconds rule their [guidelines](https://consensys.github.io/smart-contract-best-practices/recommendations/#timestamp-dependence), which states that it is safe to use _block.timestamp,_ if your time depending code can deal with a 15 second variation.

### Audit Result

**Although the block timestamp is used in various places, the specific uses are able to tolerate 15 second variations.**

## Denial of Service Attack Prevention

### Description

Denial of Service attacks can occur when a transaction depends on the outcome of an external call. A typical example of this some activity to be carried out after an Ether transfer. If the receiver is another contract, it can reject the transfer causing the whole transaction to fail.

### Audit Result

**The contracts avoid DoS attacks of this type.**

## Block Gas Limit

### Description

Contract transactions can sometimes be forced to always fails by making them exceed the maximum amount of gas that can be included in a block. The classic example of this is explained in [this explanation](https://consensys.github.io/smart-contract-best-practices/known_attacks/#dos-with-block-gas-limit) of an auction contract. Forcing the contract to refund many small bids, which are not accepted, will bump up the gas used and, if this exceeds the block gas limit, the whole transaction will fail.

The solution to this problem is avoiding situations in which many transaction calls can be caused by the same function invocation, especially if the number of calls can be influenced externally.

### Audit result

**The contracts have no block gas limit issues that could be exploited for denial of service scenarios by external user. To avoid this, certain loops over various-sized arrays are broken up into smaller iterations.**

**However, there may be accidental block gas limit issues with a large number of airdrops being registered by the contract owner (see issue description above).**

## Community Audited Code

### Description

It always best to re-use community audited code when available, such as the [code provided by Open Zeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).

### Audit Result

**The contracts uses the Open Zeppelin provided code extensively: (**[**https://github.com/OpenZeppelin/openzeppelin-contracts**](https://github.com/OpenZeppelin/openzeppelin-contracts)**).**



# Gas Usage Analysis

### Description

Gas usage of smart contracts is very important. Gas is charged for each operation that alters state, i.e. a write transaction. In contrast, read-only queries can be processed by local nodes and therefore do not have an associated cost.

Excessive gas usage may make contracts unusable in practice, in particular in times of network congestion when the gas price has to be increased to incentivize miners to prioritize transactions.

Furthermore, issues with excessive gas usage can lead to exceeding the block gas limit preventing transactions from completing. This is particularly dangerous in the case of executing code in unbounded loops, for example iterating over a variable size array. If the size of the array can be influenced by a public contract call, this can be used to create Denial of Service Attacks.

For these reasons, the present smart contract audit includes a gas usage analysis performed in two steps:

1. The code has been analyzed using automated gas estimation tools that return a relatively accurate estimate of the gas usage of each function.
2. As automated, gas estimation has its limits, a manual line by line analysis for gas related issues has also been performed.

### Audit Result

It is obvious that care has been taken to implement all functions as compact and gas efficiently as possible.

In general, gas usage is very reasonable.