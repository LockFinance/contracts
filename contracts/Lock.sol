pragma solidity 0.5.15;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";


/**
* @dev This contract will hold user locked funds which will be unlocked after
* lock-up period ends
*/
contract Lock is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    enum Status { _, OPEN, CLOSED }
    enum Fee {_, ETH, TOKEN, LOCK}

    mapping(address => bool) private tokenVsEmergencyUnlock;

    mapping(address => uint256) private _lockedTokenAmount;


    IERC20 private _lockToken;

    uint256 private _feeInToken;
    uint256 private _feeInEth;
    //Fee per lock in lock token
    uint256 private _feeInLockToken;

    //Wallet where fees will go
    address payable private _wallet;

    address constant private ETH_ADDRESS = address(
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    );

    struct LockedAsset {
        address token;// Token address
        uint256 amount;// Amount locked
        uint256 startDate;// Start date. We can remove this later
        uint256 endDate;
        uint256 amountReleased;
        uint256 periods;
        uint256 periodsReleased;
        address payable beneficiary;// Beneficary who will receive funds
        Status status;
    }

    struct Airdrop {
        address destToken;
        //numerator and denominator will be used to calculate ratio
        //Example 1DAI will get you 4 SAI
        //which means numerator = 4 and denominator = 1
        uint256 numerator;
        uint256 denominator;
        uint256 date;// Date at which time this entry was made
        //Only those locked asset which were locked before this date will be
        //given airdropped tokens
    }

    //Mapping of base token versus airdropped token
    mapping(address => Airdrop[]) private _baseTokenVsAirdrops;

    LockedAsset[] private _lockedAssets;

    //list of all asset ids for a user/beneficiary
    mapping(address => uint256[]) private _userVsLockIds;

    bool private _paused;

    event WalletChanged(address indexed wallet);
    event AssetLocked(
        address indexed token,
        address indexed sender,
        address indexed beneficiary,
        uint256 id,
        uint256 amount,
        uint256 startDate,
        uint256 endDate,
        uint256 periods,
        Fee feeMode,
        uint256 fee
    );
    event EmergencyUnlock(address indexed token, bool lock);

    event Paused();
    event Unpaused();

    event AssetClaimed(
        uint256 indexed id,
        address indexed beneficiary,
        address indexed token,
        uint256 amount
    );

    event LockClosed(
        uint256 indexed id,
        address indexed beneficiary,
        address indexed token
    );

    event AirdropAdded(
        address indexed baseToken,
        address indexed destToken,
        uint256 index,
        uint256 airdropDate,
        uint256 numerator,
        uint256 denominator
    );

    event AirdropUpdated(
        address indexed baseToken,
        address indexed destToken,
        uint256 index,
        uint256 airdropDate,
        uint256 numerator,
        uint256 denominator
    );

    event TokensAirdropped(
        address indexed destToken,
        uint256 amount
    );

    event TokensAirdroppedFailed(
        address indexed destToken,
        uint256 amount,
        address indexed user,
        string reason
    );

    event LockTokenUpdated(address indexed lockTokenAddress);
    event LockTokenFeeUpdated(uint256 fee);
    event TokenFeeUpdated(uint256 fee);
    event EthFeeUpdated(uint256 fee);


    modifier canLockAsset(address token) {
    
        require(
            !tokenVsEmergencyUnlock[token],
            "Lock: Token is in emergency unlock state!!"
        );
        _;
    }

    modifier canClaim(uint256 id) {

        require(claimable(id), "Lock: Can't claim asset");

        require(
            _lockedAssets[id].beneficiary == msg.sender,
            "Lock: Unauthorized access!!"
        );
        _;
    }

    /**
    * @dev Modifier to make a function callable only when the contract is not paused.
    */
    modifier whenNotPaused() {
        require(!_paused, "Lock: paused");
        _;
    }

    /**
    * @dev Modifier to make a function callable only when the contract is paused.
    */
    modifier whenPaused() {
        require(_paused, "Lock: not paused");
        _;
    }

    /**
    * @dev Constructor
    * @param wallet Wallet address where fees will go
    * @param lockTokenAddress Address of the lock token
    * @param lockTokenFee Fee for each lock in lock token
    * @param feeInToken Fee for each lock in token being locked
    * @param feeInEth Fee for each lock in ETH
    */
    constructor(
        address payable wallet,
        address lockTokenAddress,
        uint256 lockTokenFee,
        uint256 feeInToken,
        uint256 feeInEth
    )
        public
    {
        require(
            wallet != address(0),
            "Lock: Please provide valid wallet address!!"
        );
        require(
            lockTokenAddress != address(0),
            "Lock: Invalid lock token address"
        );
        _lockToken = IERC20(lockTokenAddress);
        _wallet = wallet;
        _feeInLockToken = lockTokenFee;
        _feeInToken = feeInToken;
        _feeInEth = feeInEth;
    }

    /**
    * @dev Returns true if the contract is paused, and false otherwise.
    */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
    * @dev returns the fee receiver wallet address
    */
    function getWallet() external view returns(address) {
        return _wallet;
    }

    function getTokensLocked(address token) external view returns(address) {
        return _lockedTokenAmount[token];
    }

    /**
    * @dev Returns lock token address
    */
    function getLockToken() external view returns(address) {
        return address(_lockToken);
    }

    /**
    * @dev Returns fee per lock in lock token
    */
    function getLockTokenFee() external view returns(uint256) {
        return _feeInLockToken;
    }

    function getTokenFee() external view returns(uint256) {
        return _feeInToken;
    }

    function getEthFee() external view returns(uint256) {
        return _feeInEth;
    }

    /**
    * @dev Returns all locked assets
    */
    function getAllLockedAssets() external view returns (
        LockedAsset[] memory
    )
    {
        return _lockedAssets;
    }

    /**
    * @dev Returns information about a locked asset
    * @param id Asset id
    */
    function getLockedAsset(
        uint256 id
    )
        external
        view
        returns(LockedAsset memory)
    {
        LockedAsset memory asset = _lockedAssets[id];
        
        return asset;
    }

    /**
    * @dev Returns all asset ids for a user
    * @param user Address of the user
    */
    function getAssetIds(
        address user
    )
        external
        view
        returns (uint256[] memory ids)
    {
        return _userVsLockIds[user];
    }

    /**
    * @dev Returns airdrop info for a given token
    * @param token Token address
    */
    function getAirdrops(address token) external view returns(
        address[] memory destTokens,
        uint256[] memory numerators,
        uint256[] memory denominators,
        uint256[] memory dates
    )
    {
        uint256 length = _baseTokenVsAirdrops[token].length;

        destTokens = new address[](length);
        numerators = new uint256[](length);
        denominators = new uint256[](length);
        dates = new uint256[](length);

        //This loop can be very costly if there are very large number of airdrops for a token.
        //Which we presume will not be the case
        for (uint256 i = 0; i < length; i++) {

            Airdrop memory airdrop = _baseTokenVsAirdrops[token][i];
            destTokens[i] = airdrop.destToken;
            numerators[i] = airdrop.numerator;
            denominators[i] = airdrop.denominator;
            dates[i] = airdrop.date;
        }

        return (
            destTokens,
            numerators,
            denominators,
            dates
        );
    }

    /**
    * @dev Returns specific airdrop for a base token
    * @param token Base token address
    * @param index Index at which this airdrop is in array
    */
    function getAirdrop(address token, uint256 index) external view returns(
        address destToken,
        uint256 numerator,
        uint256 denominator,
        uint256 date
    )
    {
        return (
            _baseTokenVsAirdrops[token][index].destToken,
            _baseTokenVsAirdrops[token][index].numerator,
            _baseTokenVsAirdrops[token][index].denominator,
            _baseTokenVsAirdrops[token][index].date
        );
    }

    /**
    * @dev Called by an admin to pause, triggers stopped state.
    */
    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused();
    }

    /**
    * @dev Called by an admin to unpause, returns to normal state.
    */
    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused();
    }

    /**
    * @dev Allows admin to set airdrop token for a given base token
    * @param baseToken Address of the base token
    * @param destToken Address of the airdropped token
    * @param numerator Numerator to calculate ratio
    * @param denominator Denominator to calculate ratio
    * @param date Date at which airdrop happened or will happen
    */
    function setAirdrop(
        address baseToken,
        address destToken,
        uint256 numerator,
        uint256 denominator,
        uint256 date
    )
        external
        onlyOwner
    {
        require(destToken != address(0), "Lock: Invalid destination token!!");
        require(numerator > 0, "Lock: Invalid numerator!!");
        require(denominator > 0, "Lock: Invalid denominator!!");

        _baseTokenVsAirdrops[baseToken].push(Airdrop({
            destToken: destToken,
            numerator: numerator,
            denominator: denominator,
            date: date
        }));

        emit AirdropAdded(
            baseToken,
            destToken,
            _baseTokenVsAirdrops[baseToken].length.sub(1),
            date,
            numerator,
            denominator
        );
    }

    /**
    * @dev Update lock token address
    * @param lockTokenAddress New lock token address
    */
    function updateLockToken(address lockTokenAddress) external onlyOwner {
        require(
            lockTokenAddress != address(0),
            "Lock: Invalid lock token address"
        );
        _lockToken = IERC20(lockTokenAddress);
        emit LockTokenUpdated(lockTokenAddress);
    }

    /**
    * @dev Update fee in lock token
    * @param lockTokenFee Fee per lock in lock token
    */
    function updateLockTokenFee(uint256 lockTokenFee) external onlyOwner {
        _feeInLockToken = lockTokenFee;
        emit LockTokenFeeUpdated(lockTokenFee);
    }

    /**
    * @dev Update fee in tokenBeing locked
    * @param feeInToken Fee per lock in token being locked
    */
    function updateFeeInToken(uint256 feeInToken) external onlyOwner {
        _feeInToken = feeInToken;
        emit TokenFeeUpdated(feeInToken);
    }

    /**
    * @dev Update fee in ETH
    * @param feeInEth Fee per lock in ETH
    */
    function updateFeeInEth(uint256 feeInEth) external onlyOwner {
        _feeInEth = feeInEth;
        emit EthFeeUpdated(feeInEth);
    }

    /**
    * @dev Allows admin to update airdrop at given index
    * @param baseToken Base token address for which airdrop has to be updated
    * @param numerator New numerator
    * @param denominator New denominator
    * @param date New airdrop date
    * @param index Index at which this airdrop resides for the basetoken
    */
    function updateAirdrop(
        address baseToken,
        uint256 numerator,
        uint256 denominator,
        uint256 date,
        uint256 index
    )
        external
        onlyOwner
    {
        require(
            _baseTokenVsAirdrops[baseToken].length > index,
            "Lock: Invalid index value!!"
        );
        require(numerator > 0, "Lock: Invalid numerator!!");
        require(denominator > 0, "Lock: Invalid denominator!!");

        Airdrop storage airdrop = _baseTokenVsAirdrops[baseToken][index];
        airdrop.numerator = numerator;
        airdrop.denominator = denominator;
        airdrop.date = date;

        emit AirdropUpdated(
            baseToken,
            airdrop.destToken,
            index,
            date,
            numerator,
            denominator
        );
    }

    /**
    * @dev Allows admin to set fee receiver wallet
    * @param wallet New wallet address
    */
    function setWallet(address payable wallet) external onlyOwner {
        require(
            wallet != address(0),
            "Lock: Please provider valid wallet address!!"
        );
        _wallet = wallet;

        emit WalletChanged(wallet);
    }

    /**
    * @dev Update emergency unlock status for token
    * @param status Sets to either true or false
    * @param token Address of the token being updated
    */
    function updateEmergencyUnlock(
        address token,
        bool status
    )
        external
        onlyOwner
    {
        tokenVsEmergencyUnlock[token] = status;
        emit EmergencyUnlock(token, status);
    }

    /**
    * @dev Allows user to lock asset. In case of ERC-20 token the user will
    * first have to approve the contract to spend on his/her behalf
    * @param tokenAddress Address of the token to be locked
    * @param amount Amount of tokens to lock
    * @param duration Duration for which tokens to be locked. In seconds
    * @param beneficiary Address of the beneficiary
    * @param periods Number of release periods
    * @param lockFee Asset in which fee is being paid
    */
    function lock(
        address tokenAddress,
        uint256 amount,
        uint256 duration,
        address payable beneficiary,
        uint256 periods,
        Fee lockFee
    )
        external
        payable
        whenNotPaused
        canLockAsset(tokenAddress)
    {
        uint256 remValue = _lock(
            tokenAddress,
            amount,
            duration,
            beneficiary,
            periods,
            msg.value,
            lockFee
        );

        require(
            remValue < 10000000000,
            "Lock: Sent more ethers then required"
        );

    }

    /**
    * @dev Allows user to lock asset. In case of ERC-20 token the user will
    * first have to approve the contract to spend on his/her behalf
    * @param tokenAddress Address of the token to be locked
    * @param amounts List of amount of tokens to lock
    * @param durations List of duration for which tokens to be locked. In seconds
    * @param beneficiaries List of addresses of the beneficiaries
    * @param periods List of number of release periods
    * @param lockFee Asset in which fee is being paid
    */
    function bulkLock(
        address tokenAddress,
        uint256[] calldata amounts,
        uint256[] calldata durations,
        address payable[] calldata beneficiaries,
        uint256[] calldata periods,
        Fee lockFee
    )
        external
        payable
        whenNotPaused
        canLockAsset(tokenAddress)
    {
        uint256 remValue = msg.value;
        require(amounts.length == durations.length, "Lock: Invalid input");
        require(amounts.length == beneficiaries.length, "Lock: Invalid input");
       

        for (uint256 i = 0; i < amounts.length; i++) {
            remValue = _lock(
                tokenAddress,
                amounts[i],
                durations[i],
                beneficiaries[i],
                periods[i],
                remValue,
                lockFee
            );
        }

        require(
            remValue < 10000000000,
            "Lock: Sent more ethers then required"
        );

    }

    /**
    * @dev Allows beneficiary of locked asset to claim asset after lock-up period ends
    * @param id Id of the locked asset
    */
    function claim(uint256 id) external canClaim(id) {
        LockedAsset memory lockedAsset = _lockedAssets[id];

        require(
            lockedAsset.status == Status.OPEN,
            "LOCK: Lock is already closed!!"
        );

        uint256 amount = 0;
        if (ETH_ADDRESS == lockedAsset.token) {
            amount = claimETH(
                id
            );
        }
        else {
            amount = _claimERC20(
                id
            );
        }

        _lockedTokenAmount[lockedAsset.token] = _lockedTokenAmount[lockedAsset.token].sub(amount);

        emit AssetClaimed(
            id,
            lockedAsset.beneficiary,
            lockedAsset.token,
            amount
        );
    }

    /**
    * @dev Returns whether given asset can be claimed or not
    * @param id id of an asset
    */
    function claimable(uint256 id) public view returns(bool){

        LockedAsset memory asset = _lockedAssets[id];
        uint256 duration = asset.endDate.sub(asset.startDate);
        uint256 durationPerPeriod = duration.div(asset.periods);
        uint256 claimAblePeriods = block.timestamp.sub(asset.startDate).div(durationPerPeriod).sub(asset.periodsReleased); 

        if (
            asset.status == Status.OPEN &&
            (
                claimAblePeriods > 0 ||
                tokenVsEmergencyUnlock[asset.token]
            )
        )
        {
            return true;
        }
        return false;
    }

    /**
    * @dev Helper method to lock asset
    */
    function _lock(
        address tokenAddress,
        uint256 amount,
        uint256 duration,
        address payable beneficiary,
        uint256 periods,
        uint256 value,
        Fee lockFee
    )
        private
        returns(uint256)
    {
        require(
            beneficiary != address(0),
            "Lock: Provide valid beneficiary address!!"
        );
        require(amount > 0, "Lock: Amount can't be 0");
        require(periods > 0, "Lock: Periods can't be 0");

        uint256 endDate = block.timestamp.add(duration);
        uint256 fee = 0;
        uint256 newAmount = 0;

        (fee, newAmount) = _calculateFee(amount, lockFee);

        _lockedTokenAmount[tokenAddress] = _lockedTokenAmount[tokenAddress].add(newAmount);

        uint256 remValue = value;

        if (ETH_ADDRESS == tokenAddress) {
            _lockETH(
                newAmount,
                fee,
                endDate,
                beneficiary,
                periods,
                value,
                lockFee
            );

            remValue = remValue.sub(amount);

            if (lockFee == Fee.ETH) {
                remValue = remValue.sub(fee);
            }
        }

        else {
            _lockERC20(
                tokenAddress,
                newAmount,
                fee,
                endDate,
                beneficiary,
                periods,
                remValue,
                lockFee
            );

            if (lockFee == Fee.ETH) {
                remValue = remValue.sub(fee);
            }
        }

        emit AssetLocked(
            tokenAddress,
            msg.sender,
            beneficiary,
            _lockedAssets.length - 1,
            newAmount,
            block.timestamp,
            endDate,
            periods,
            lockFee,
            fee
        );

        return remValue;
    }

    /**
    * @dev Helper method to lock ETH
    */
    function _lockETH(
        uint256 amount,
        uint256 fee,
        uint256 endDate,
        address payable beneficiary,
        uint256 periods,
        uint256 value,
        Fee lockFee
    )
        private
    {

        //Transferring fee to the wallet

        if (lockFee == Fee.LOCK) {
            require(value >= amount, "Lock: Enough ETH not sent!!");
            _lockToken.safeTransferFrom(msg.sender, _wallet, fee);
        }
        else {
            require(value >= amount.add(fee), "Lock: Enough ETH not sent!!");
            (bool success,) = _wallet.call.value(fee)("");
            require(success, "Lock: Transfer of fee failed");
        }

        _lockedAssets.push(LockedAsset({
            token: ETH_ADDRESS,
            amount: amount,
            startDate: block.timestamp,
            endDate: endDate,
            periods: periods,
            amountReleased: 0,
            periodsReleased: 0,
            beneficiary: beneficiary,
            status: Status.OPEN
        }));
        _userVsLockIds[beneficiary].push(_lockedAssets.length - 1);
    }

    /**
    * @dev Helper method to lock ERC-20 tokens
    */
    function _lockERC20(
        address token,
        uint256 amount,
        uint256 fee,
        uint256 endDate,
        address payable beneficiary,
        uint256 periods,
        uint256 value,
        Fee lockFee
    )
        private
    {

        //Transfer fee to the wallet
        if (lockFee == Fee.LOCK) {
            _lockToken.safeTransferFrom(msg.sender, _wallet, fee);
        }
        else if (lockFee == Fee.ETH) {
            require(value >= fee, ";Lock: Enough ETH not sent!!");
            (bool success,) = _wallet.call.value(fee)("");
            require(success, "Lock: Transfer of fee failed");
        }
        else {
            IERC20(token).safeTransferFrom(msg.sender, _wallet, fee);
        }
        
        //Transfer required amount of tokens to the contract from user balance
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _lockedAssets.push(LockedAsset({
            token: token,
            amount: amount,
            startDate: block.timestamp,
            endDate: endDate,
            periods: periods,
            amountReleased: 0,
            periodsReleased: 0,
            beneficiary: beneficiary,
            status: Status.OPEN
        }));
        _userVsLockIds[beneficiary].push(_lockedAssets.length - 1);
    }

    /**
    * @dev Helper method to claim ETH
    */
    function _claimETH(uint256 id) private returns (uint256) {
        LockedAsset storage asset = _lockedAssets[id];
        
        uint256 duration = asset.endDate.sub(asset.startDate);
        uint256 durationPerPeriod = duration.div(asset.periods);
        uint256 claimAblePeriods = block.timestamp
        .sub(asset.startDate)
        .div(durationPerPeriod)
        .sub(asset.periodsReleased);

        if (
                claimAblePeriods.add(asset.periodsReleased) > asset.periods
            )
        {
            claimAblePeriods = asset.periods.sub(asset.periodsReleased);
        }

        asset.periodsReleased = asset.periodsReleased.add(claimAblePeriods);

        uint256 amount = asset.amount.mul(claimAblePeriods).div(asset.periods);

        require(amount > 0, "LOCK: Nothing available to claim");

        if (asset.periodsReleased == asset.periods) {
            amount = asset.amount.sub(asset.amountReleased);
            asset.status = Status.CLOSED;

            _claimAirdroppedTokens(
                asset.token,
                asset.startDate,
                asset.amount
            );

            emit LockClosed(id, msg.sender, ETH_ADDRESS);
        }

        asset.amountReleased = asset.amountReleased.add(amount);

        (bool success,) = msg.sender.call.value(amount)("");
        require(success, "Lock: Failed to transfer eth!!");

        return amount;
    }

    /**
    * @dev Helper method to claim ERC-20
    */
    function _claimERC20(uint256 id) private returns(uint256) {
        LockedAsset storage asset = _lockedAssets[id];

        uint256 duration = asset.endDate.sub(asset.startDate);
        uint256 durationPerPeriod = duration.div(asset.periods);
        uint256 claimAblePeriods = block.timestamp.sub(asset.startDate).div(durationPerPeriod).sub(asset.periodsReleased); 

        if(claimAblePeriods.add(asset.periodsReleased) > asset.periods ) {
            claimAblePeriods = asset.periods.sub(asset.periodsReleased);
        }
        asset.periodsReleased = asset.periodsReleased.add(claimAblePeriods);

        uint256 amount = asset.amount.mul(claimAblePeriods).div(asset.periods);

        require(amount > 0, "LOCK: Nothing available to claim");

        if (asset.periodsReleased == asset.periods) {
            amount = asset.amount.sub(asset.amountReleased);
            asset.status = Status.CLOSED;

            _claimAirdroppedTokens(
                asset.token,
                asset.startDate,
                asset.amount
            );

            emit LockClosed(id, msg.sender, asset.token);
        }

        asset.amountReleased = asset.amountReleased.add(amount);

        IERC20(asset.token).safeTransfer(msg.sender, amount);

        return amount;
    }

    /**
    * @dev Helper method to claim airdropped tokens
    * @param baseToken Base Token address
    * @param lastLocked Date when base tokens were last locked
    * @param amount Amount of base tokens locked
    */
    function _claimAirdroppedTokens(
        address baseToken,
        uint256 lastLocked,
        uint256 amount
    )
        private
    {
        //This loop can be very costly if number of airdropped tokens
        //for base token is very large. But we assume that it is not going to be the case
        for (uint256 i = 0; i < _baseTokenVsAirdrops[baseToken].length; i++) {

            Airdrop memory airdrop = _baseTokenVsAirdrops[baseToken][i];

            if (airdrop.date > lastLocked && airdrop.date < block.timestamp) {
                uint256 airdropAmount = amount.mul(airdrop.numerator).div(airdrop.denominator);
                uint256 tokenBalance = getTokenBalance(airdrop.destToken, address(this));
                if (
                    _lockedTokenAmount.add(airdropAmount) <= tokenBalance
                ) {
                    transferTokens(airdrop.destToken, msg.sender, airdropAmount);
                    emit TokensAirdropped(airdrop.destToken, airdropAmount);
                }
                else {
                    emit TokensAirdroppedFailed(
                        airdrop.destToken,
                        airdropAmount,
                        msg.sender,
                        "Trying to airdrop more tokens then available in the contract"
                    );
                }
            }
        }

    }

    function getTokenBalance(
        address token,
        address account
    )
        private
        view
        returns(uint256)
    {
        if (ETH_ADDRESS == token) {
            return account.balance;
        }
        else {
            return IERC20(token).balanceOf(account);
        }
    }

    function transferTokens(
        address token,
        address payable account,
        uint256 amount
    )
        private
    {
        if (amount > 0) {
            if (token == ETH_ADDRESS) {
                (bool result, ) = account.call{value: amount}("");
                require(result, "Failed to transfer Ether");
            }
            else {
                IERC20(token).safeTransfer(account, amount);
            }
        }
    }

    //Helper method to calculate fee
    function _calculateFee(
        uint256 amount,
        Fee lockFee
    )
        private
        view
        returns(uint256 fee, uint256 newAmount)
    {
        newAmount = amount;

        if (lockFee == Fee.ETH) {
            fee = _feeInEth;
        }
        else if (lockFee == Fee.LOCK) {
            fee = _feeInLockToken;
        }
        else {
            fee = amount.mul(_feeInToken).div(10000);
            newAmount = amount.sub(fee);
        }
        return(fee, newAmount);
    }
}
