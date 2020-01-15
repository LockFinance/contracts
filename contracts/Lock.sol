pragma solidity 0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";


/**
* @dev This contract will hold user locked funds which will be unlocked after
* lock-up period ends
*/
contract Lock is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    enum Status { _, OPEN, CLOSED }
    enum TokenStatus {_, ACTIVE, INACTIVE }

    struct Token {
        address tokenAddress;
        uint256 minAmount;
        bool emergencyUnlock;
        TokenStatus status;
    }

    Token[] private _tokens;

    //Keeps track of token index in above array
    mapping(address => uint256) private _tokenVsIndex;

    //Fee to be paid for each lock-up
    //In percentage
    //Ex. for 1% enter 100. For 1.25% enter 125
    uint256 private _fee;

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

    //Global lockedasset id. Also give total number of lock-ups made so far
    uint256 private _lockId;

    //list of all asset ids for a user/beneficiary
    mapping(address => uint256[]) private _userVsLockIds;

    mapping(uint256 => LockedAsset) private _idVsLockedAsset;

    bool private _paused;

    event TokenAdded(address indexed token);
    event TokenInactivated(address indexed token);
    event TokenActivated(address indexed token);
    event FeeChanged(uint256 fee);
    event WalletChanged(address indexed wallet);
    event AssetLocked(
        address indexed token,
        address indexed sender,
        address indexed beneficiary,
        uint256 id,
        uint256 amount,
        uint256 startDate,
        uint256 endDate
    );
    event TokenUpdated(
        uint256 indexed id,
        address indexed token,
        uint256 minAmount,
        bool emergencyUnlock
    );
    event Paused();
    event Unpaused();

    event AssetClaimed(
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

    modifier tokenExist(address token) {
        require(_tokenVsIndex[token] > 0, "Lock: Token does not exist!!");
        _;
    }

    modifier tokenDoesNotExist(address token) {
        require(_tokenVsIndex[token] == 0, "Lock: Token already exist!!");
        _;
    }

    modifier canLockAsset(address token) {
        uint256 index = _tokenVsIndex[token];

        require(index > 0, "Lock: Token does not exist!!");

        require(
            _tokens[index.sub(1)].status == TokenStatus.ACTIVE,
            "Lock: Token not active!!"
        );

        require(
            !_tokens[index.sub(1)].emergencyUnlock,
            "Lock: Token is in emergency unlock state!!"
        );
        _;
    }

    modifier canClaim(uint256 id) {

        require(claimable(id), "Lock: Can't claim asset");

        require(
            _idVsLockedAsset[id].beneficiary == msg.sender,
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
    * @dev constructor
    * @param fee Fee to be paid for each lock-up
    * @param wallet Wallet address where fees will go
    * @param tokens List of tokens
    * @param minAmount Min lock-up amount for each token
    */
    constructor(
        uint256 fee,
        address payable wallet,
        address[] memory tokens,
        uint256[] memory minAmount
    )
        public
    {
        require(
            tokens.length == minAmount.length,
            "Lock: Length mismatch between token list and their minimum lock amount!!"
        );
        require(
            wallet != address(0),
            "Lock: Please provide valid wallet address!!"
        );

        _wallet = wallet;
        _fee = fee;

        for(uint256 i = 0; i<tokens.length; i = i.add(1)) {
            require(
                _tokenVsIndex[tokens[i]] == 0,
                "Lock: Token already exists"
            );
            _tokens.push(Token({
                tokenAddress: tokens[i],
                minAmount: minAmount[i],
                emergencyUnlock: false,
                status: TokenStatus.ACTIVE
            }));
            _tokenVsIndex[tokens[i]] = _tokens.length;

            emit TokenAdded(tokens[i]);
        }

    }

    /**
    * @dev Returns true if the contract is paused, and false otherwise.
    */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
    * @dev returns lock-up fee
    */
    function getFee() external view returns(uint256) {
        return _fee;
    }

    /**
    * @dev returns the fee receiver wallet address
    */
    function getWallet() external view returns(address) {
        return _wallet;
    }

    /**
    * @dev Returns total token count
    */
    function getTokenCount() external view returns(uint256) {
        return _tokens.length;
    }

    /**
    * @dev Returns list of supported tokens
    * This will be a paginated method which will only send 15 tokens in one request
    * This is done to prevent infinite loops and overflow of gas limits
    * @param start start index for pagination
    * @param length Amount of tokens to fetch
    */
    function getTokens(uint256 start, uint256 length) external view returns(
        address[] memory tokenAddresses,
        uint256[] memory minAmounts,
        bool[] memory emergencyUnlocks,
        TokenStatus[] memory statuses
    )
    {
        tokenAddresses = new address[](length);
        minAmounts = new uint256[](length);
        emergencyUnlocks = new bool[](length);
        statuses = new TokenStatus[](length);

        require(start.add(length) <= _tokens.length, "Lock: Invalid input");
        require(length > 0 && length <= 15, "Lock: Invalid length");
        uint256 count = 0;
        for(uint256 i = start; i < start.add(length); i++) {
            tokenAddresses[count] = _tokens[i].tokenAddress;
            minAmounts[count] = _tokens[i].minAmount;
            emergencyUnlocks[count] = _tokens[i].emergencyUnlock;
            statuses[count] = _tokens[i].status;
            count = count.add(1);
        }

        return(
            tokenAddresses,
            minAmounts,
            emergencyUnlocks,
            statuses
        );
    }

    /**
    * @dev Returns information about specific token
    * @dev tokenAddress Address of the token
    */
    function getTokenInfo(address tokenAddress) external view returns(
        uint256 minAmount,
        bool emergencyUnlock,
        TokenStatus status
    )
    {
        uint256 index = _tokenVsIndex[tokenAddress];

        if(index > 0){
            index = index.sub(1);
            Token memory token = _tokens[index];
            return (
                token.minAmount,
                token.emergencyUnlock,
                token.status
            );
        }
    }

    /**
    * @dev Returns information about a locked asset
    * @param id Asset id
    */
    function getLockedAsset(uint256 id) external view returns(
        address token,
        uint256 amount,
        uint256 startDate,
        uint256 endDate,
        address beneficiary,
        Status status
    )
    {
        LockedAsset memory asset = _idVsLockedAsset[id];
        token = asset.token;
        amount = asset.amount;
        startDate = asset.startDate;
        endDate = asset.endDate;
        beneficiary = asset.beneficiary;
        status = asset.status;

        return(
            token,
            amount,
            startDate,
            endDate,
            beneficiary,
            status
        );
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
        for(uint256 i = 0; i < length; i++){

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
            _baseTokenVsAirdrops[baseToken].length.sub(1),
            date,
            numerator,
            denominator
        );
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
    * @dev Allows admin to set fee
    * @param fee New fee values
    */
    function setFee(uint256 fee) external onlyOwner {
        _fee = fee;
        emit FeeChanged(fee);
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
    * @dev Allows admin to update token info
    * @param tokenAddress Address of the token to be updated
    * @param minAmount Min amount of tokens required to lock
    * @param emergencyUnlock If token is in emergency unlock state
    */
    function updateToken(
        address tokenAddress,
        uint256 minAmount,
        bool emergencyUnlock
    )
        external
        onlyOwner
        tokenExist(tokenAddress)
    {
        uint256 index = _tokenVsIndex[tokenAddress].sub(1);
        Token storage token = _tokens[index];
        token.minAmount = minAmount;
        token.emergencyUnlock = emergencyUnlock;
        
        emit TokenUpdated(
            index,
            tokenAddress,
            minAmount,
            emergencyUnlock
        );
    }

    /**
    * @dev Allows admin to add new token to the list
    * @param token Address of the token
    * @param minAmount Minimum amount of tokens to lock for this token
    */
    function addToken(
        address token,
        uint256 minAmount
    )
        external
        onlyOwner
        tokenDoesNotExist(token)
    {
        _tokens.push(Token({
            tokenAddress: token,
            minAmount: minAmount,
            emergencyUnlock: false,
            status: TokenStatus.ACTIVE
        }));
        _tokenVsIndex[token] = _tokens.length;

        emit TokenAdded(token);
    }


    /**
    * @dev Allows admin to inactivate token
    * @param token Address of the token to be inactivated
    */
    function inactivateToken(
        address token
    )
        external
        onlyOwner
        tokenExist(token)
    {
        uint256 index = _tokenVsIndex[token].sub(1);

        require(
            _tokens[index].status == TokenStatus.ACTIVE,
            "Lock: Token already inactive!!"
        );

        _tokens[index].status = TokenStatus.INACTIVE;

        emit TokenInactivated(token);
    }

    /**
    * @dev Allows admin to activate any existing token
    * @param token Address of the token to be activated
    */
    function activateToken(
        address token
    )
        external
        onlyOwner
        tokenExist(token)
    {
        uint256 index = _tokenVsIndex[token].sub(1);

        require(
            _tokens[index].status == TokenStatus.INACTIVE,
            "Lock: Token already active!!"
        );

        _tokens[index].status = TokenStatus.ACTIVE;

        emit TokenActivated(token);
    }

    /**
    * @dev Allows user to lock asset. In case of ERC-20 token the user will
    * first have to approve the contract to spend on his/her behalf
    * @param tokenAddress Address of the token to be locked
    * @param amount Amount of tokens to lock
    * @param duration Duration for which tokens to be locked. In seconds
    * @param beneficiary Address of the beneficiary
    */
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
        uint256 remValue = _lock(
            tokenAddress,
            amount,
            duration,
            beneficiary,
            msg.value
        );

        require(remValue == 0, "Lock: Sent more ethers then required");

    }

    /**
    * @dev Allows user to lock asset. In case of ERC-20 token the user will
    * first have to approve the contract to spend on his/her behalf
    * @param tokenAddress Address of the token to be locked
    * @param amounts List of amount of tokens to lock
    * @param durations List of duration for which tokens to be locked. In seconds
    * @param beneficiaries List of addresses of the beneficiaries
    */
    function bulkLock(
        address tokenAddress,
        uint256[] calldata amounts,
        uint256[] calldata durations,
        address payable[] calldata beneficiaries
    )
        external
        payable
        whenNotPaused
        canLockAsset(tokenAddress)
    {
        uint256 remValue = msg.value;
        require(amounts.length == durations.length, "Lock: Invalid input");
        require(amounts.length == beneficiaries.length, "Lock: Invalid input");

        for(uint256 i = 0; i < amounts.length; i++){
            remValue = _lock(
                tokenAddress,
                amounts[i],
                durations[i],
                beneficiaries[i],
                remValue
            );
        }

        require(remValue == 0, "Lock: Sent more ethers then required");

    }

    /**
    * @dev Allows beneficiary of locked asset to claim asset after lock-up period ends
    * @param id Id of the locked asset
    */
    function claim(uint256 id) external canClaim(id) {
        LockedAsset memory lockedAsset = _idVsLockedAsset[id];
        if(ETH_ADDRESS == lockedAsset.token) {
            _claimETH(
                id
            );
        }

        else {
            _claimERC20(
                id
            );
        }

        emit AssetClaimed(
            id,
            lockedAsset.beneficiary,
            lockedAsset.token
        );
    }

    /**
    * @dev Returns whether given asset can be claimed or not
    * @param id id of an asset
    */
    function claimable(uint256 id) public view returns(bool){

        if(
            _idVsLockedAsset[id].status == Status.OPEN &&
            (
                _idVsLockedAsset[id].endDate <= block.timestamp ||
                _tokens[_tokenVsIndex[_idVsLockedAsset[id].token].sub(1)].emergencyUnlock
            )
        )
        {
            return true;
        }
        return false;
    }

    /**
    * @dev Returns whether provided token is active or not
    * @param token Address of the token to be checked
    */
    function isActive(address token) public view returns(bool) {
        uint256 index = _tokenVsIndex[token];

        if(index > 0){
            return (_tokens[index.sub(1)].status == TokenStatus.ACTIVE);
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
        uint256 value
    )
        private
        returns(uint256)
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
        uint256 remValue = value;

        if(ETH_ADDRESS == tokenAddress) {
            _lockETH(
                newAmount,
                fee,
                endDate,
                beneficiary,
                value
            );

            remValue = remValue.sub(amount);
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
        uint256 value
    )
        private
    {

        //Transferring fee to the wallet
        require(value >= amount.add(fee), "Lock: Enough ETH not sent!!");

        (bool success,) = _wallet.call.value(fee)("");
        require(success, "Lock: Transfer of fee failed");

        _lockId = _lockId.add(1);

        _idVsLockedAsset[_lockId] = LockedAsset({
            token: ETH_ADDRESS,
            amount: amount,
            startDate: block.timestamp,
            endDate: endDate,
            beneficiary: beneficiary,
            status: Status.OPEN
        });
        _userVsLockIds[beneficiary].push(_lockId);
    }

    /**
    * @dev Helper method to lock ERC-20 tokens
    */
    function _lockERC20(
        address token,
        uint256 amount,
        uint256 fee,
        uint256 endDate,
        address payable beneficiary
    )
        private
    {

        //Transfer fee to the wallet
        IERC20(token).safeTransferFrom(msg.sender, _wallet, fee);

        //Transfer required amount of tokens to the contract from user balance
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _lockId = _lockId.add(1);

        _idVsLockedAsset[_lockId] = LockedAsset({
            token: token,
            amount: amount,
            startDate: block.timestamp,
            endDate: endDate,
            beneficiary: beneficiary,
            status: Status.OPEN
        });
        _userVsLockIds[beneficiary].push(_lockId);
    }

    /**
    * @dev Helper method to claim ETH
    */
    function _claimETH(uint256 id) private {
        LockedAsset storage asset = _idVsLockedAsset[id];
        asset.status = Status.CLOSED;
        (bool success,) = msg.sender.call.value(asset.amount)("");
        require(success, "Lock: Failed to transfer eth!!");

        _claimAirdroppedTokens(
            asset.token,
            asset.startDate,
            asset.amount
        );
    }

    /**
    * @dev Helper method to claim ERC-20
    */
    function _claimERC20(uint256 id) private {
        LockedAsset storage asset = _idVsLockedAsset[id];
        asset.status = Status.CLOSED;
        IERC20(asset.token).safeTransfer(msg.sender, asset.amount);
        _claimAirdroppedTokens(
            asset.token,
            asset.startDate,
            asset.amount
        );
    }

    /**
    * @dev Helper method to claim airdropped tokens
    * @param baseToken Base Token address
    * @param lockDate Date when base tokens were locked
    * @param amount Amount of base tokens locked
    */
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

            if(airdrop.date > lockDate && airdrop.date < block.timestamp) {
                uint256 airdropAmount = amount.mul(airdrop.numerator).div(airdrop.denominator);
                IERC20(airdrop.destToken).safeTransfer(msg.sender, airdropAmount);
                emit TokensAirdropped(airdrop.destToken, airdropAmount);
            }
        }

    }
}
