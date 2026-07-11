// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title LockVault
 * @notice Permissionless token locking and vesting. Lock any ERC-20 or native
 *         ETH until a future date, optionally with a linear vesting schedule
 *         and cliff. Every lock is minted as a transferable ERC-721 position,
 *         so locks show up in wallets, can be moved to cold storage, and are
 *         composable with the rest of the ecosystem.
 *
 *         Trust model — what the owner can NOT do:
 *         - cannot touch or unlock user funds (no emergency-unlock backdoor);
 *         - cannot set the protocol fee above `MAX_FEE_BPS` (1%);
 *         - cannot block claims: `pause` only stops creation of new locks.
 *
 * @dev    Token addresses: native ETH is represented by `address(0)`.
 *         Fee-on-transfer tokens are supported — the position records the
 *         amount actually received by the vault.
 */
contract LockVault is ERC721Enumerable, Ownable2Step, ReentrancyGuard, Pausable, Multicall {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using Strings for address;

    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @notice A lock position. Amounts vest linearly from `start` to `end`;
    ///         nothing is claimable before `cliff`. A pure time-lock has
    ///         `start == cliff == end`.
    struct Position {
        address token; //   token locked, address(0) for native ETH
        uint48 start; //    vesting starts (== end for a pure time-lock)
        uint48 cliff; //    nothing claimable before this timestamp
        uint48 end; //      fully vested / unlocked at this timestamp
        uint128 amount; //  total amount locked (net of protocol fee)
        uint128 claimed; // amount already claimed
    }

    struct LockParams {
        address token;
        uint256 amount;
        uint48 start;
        uint48 cliff;
        uint48 end;
        address beneficiary;
    }

    // ---------------------------------------------------------------------
    // Constants / immutables
    // ---------------------------------------------------------------------

    /// @notice Hard cap on the protocol fee: 100 bps = 1%.
    uint256 public constant MAX_FEE_BPS = 100;

    /// @notice Basis-point denominator.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Longest allowed lock/vesting duration (guards against fat-finger dates).
    uint256 public constant MAX_DURATION = 100 * 365 days;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Protocol fee in basis points, deducted from each deposit.
    uint256 public feeBps;

    /// @notice Receiver of protocol fees and swept surplus.
    address public feeRecipient;

    /// @notice Next position id (ids start at 1).
    uint256 public nextId = 1;

    /// @notice Position data by token id.
    mapping(uint256 id => Position) private _positions;

    /// @notice Amount of each token the vault holds on behalf of positions.
    ///         Anything above this is surplus and can be swept.
    mapping(address token => uint256) public totalLocked;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Locked(
        uint256 indexed id,
        address indexed token,
        address indexed beneficiary,
        address funder,
        uint256 amount,
        uint256 fee,
        uint48 start,
        uint48 cliff,
        uint48 end
    );
    event Claimed(uint256 indexed id, address indexed token, address indexed beneficiary, uint256 amount);
    event ToppedUp(uint256 indexed id, address indexed funder, uint256 amount, uint256 fee);
    event Extended(uint256 indexed id, uint48 oldEnd, uint48 newEnd);
    event Split(uint256 indexed id, uint256 indexed newId, uint256 amountMoved);
    event FeeUpdated(uint256 feeBps);
    event FeeRecipientUpdated(address feeRecipient);
    event Swept(address indexed token, address indexed to, uint256 amount);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAmount();
    error ZeroAddress();
    error InvalidSchedule();
    error DurationTooLong();
    error FeeTooHigh();
    error WrongMsgValue();
    error NativeTokenTopUpMismatch();
    error NothingToClaim();
    error NotPositionOwner();
    error EthTransferFailed();
    error AmountTooLarge();
    error SplitAmountInvalid();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address initialOwner, address feeRecipient_, uint256 feeBps_)
        ERC721("Lock Finance Positions", "LOCKPOS")
        Ownable(initialOwner)
    {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert FeeTooHigh();
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
    }

    // ---------------------------------------------------------------------
    // Locking
    // ---------------------------------------------------------------------

    /**
     * @notice Lock tokens until `unlockAt` (a pure time-lock, no vesting).
     * @param token       ERC-20 to lock, or address(0) for native ETH.
     * @param amount      Amount to deposit. For ETH must equal `msg.value` exactly.
     * @param unlockAt    Timestamp when the full amount becomes claimable.
     * @param beneficiary Receiver of the position NFT.
     * @return id         The minted position id.
     */
    function lock(address token, uint256 amount, uint48 unlockAt, address beneficiary)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 id)
    {
        return _lock(LockParams(token, amount, unlockAt, unlockAt, unlockAt, beneficiary), msg.value);
    }

    /**
     * @notice Lock tokens with a linear vesting schedule.
     * @param token       ERC-20 to lock, or address(0) for native ETH.
     * @param amount      Amount to deposit. For ETH must equal `msg.value` exactly.
     * @param start       Vesting start. Amounts vest linearly from `start` to `end`.
     * @param cliff       Nothing is claimable before this timestamp (>= start).
     * @param end         Fully vested at this timestamp (>= cliff, > now).
     * @param beneficiary Receiver of the position NFT.
     * @return id         The minted position id.
     */
    function lockVesting(
        address token,
        uint256 amount,
        uint48 start,
        uint48 cliff,
        uint48 end,
        address beneficiary
    ) external payable nonReentrant whenNotPaused returns (uint256 id) {
        return _lock(LockParams(token, amount, start, cliff, end, beneficiary), msg.value);
    }

    /**
     * @notice Lock an EIP-2612 token in a single transaction using a permit
     *         signature. The permit call is best-effort: if it fails (e.g. it
     *         was front-run and already consumed) the existing allowance is used.
     */
    function lockWithPermit(
        LockParams calldata params,
        uint256 permitValue,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused returns (uint256 id) {
        if (params.token == address(0)) revert ZeroAddress();
        try IERC20Permit(params.token).permit(msg.sender, address(this), permitValue, deadline, v, r, s) {} catch {}
        return _lock(params, 0);
    }

    /**
     * @notice Create several locks in one transaction. For native ETH locks the
     *         sum of amounts must equal `msg.value` exactly.
     */
    function batchLock(LockParams[] calldata params)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256[] memory ids)
    {
        uint256 remainingValue = msg.value;
        ids = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            uint256 valueForLock = 0;
            if (params[i].token == address(0)) {
                if (remainingValue < params[i].amount) revert WrongMsgValue();
                remainingValue -= params[i].amount;
                valueForLock = params[i].amount;
            }
            ids[i] = _lock(params[i], valueForLock);
        }
        if (remainingValue != 0) revert WrongMsgValue();
    }

    /**
     * @notice Add funds to an existing position. Anyone may top up any position;
     *         the added amount follows the position's existing schedule.
     * @param id     Position id.
     * @param amount Amount to add. For ETH positions must equal `msg.value`.
     */
    function topUp(uint256 id, uint256 amount) external payable nonReentrant whenNotPaused {
        _requireOwned(id);
        Position storage p = _positions[id];

        (uint256 net, uint256 fee) = _collect(p.token, amount, msg.value);

        uint256 newAmount = uint256(p.amount) + net;
        if (newAmount > type(uint128).max) revert AmountTooLarge();
        p.amount = uint128(newAmount);
        totalLocked[p.token] += net;

        emit ToppedUp(id, msg.sender, net, fee);
    }

    /**
     * @notice Push a position's unlock further into the future. Only the
     *         position owner may extend, and only to a later date.
     */
    function extend(uint256 id, uint48 newEnd) external {
        if (_ownerOf(id) != msg.sender) revert NotPositionOwner();
        Position storage p = _positions[id];

        if (newEnd <= p.end) revert InvalidSchedule();
        if (uint256(newEnd) > block.timestamp + MAX_DURATION) revert DurationTooLong();

        uint48 oldEnd = p.end;
        // A pure time-lock keeps its shape: cliff and start follow the end.
        if (p.cliff == oldEnd && p.start == oldEnd) {
            p.start = newEnd;
            p.cliff = newEnd;
        } else if (p.cliff == oldEnd) {
            p.cliff = newEnd;
        }
        p.end = newEnd;

        emit Extended(id, oldEnd, newEnd);
    }

    /**
     * @notice Split an unclaimed slice of a position into a new position with
     *         the same schedule. Useful for selling or delegating part of a
     *         locked bag without touching the rest.
     * @param id     Position to split.
     * @param amount Amount of the *unclaimed* balance to move to the new position.
     * @param to     Owner of the new position.
     * @return newId The id of the newly minted position.
     */
    function split(uint256 id, uint256 amount, address to) external nonReentrant returns (uint256 newId) {
        if (_ownerOf(id) != msg.sender) revert NotPositionOwner();
        if (to == address(0)) revert ZeroAddress();
        Position storage p = _positions[id];

        if (amount == 0 || amount >= p.amount) revert SplitAmountInvalid();

        // Move a pro-rata share of `claimed` along with the slice so both
        // positions keep exact vesting math (claimable is conserved across
        // the split, up to 1 wei of rounding absorbed by the new position).
        uint256 movedClaimed = (uint256(p.claimed) * amount) / p.amount;
        p.amount = uint128(uint256(p.amount) - amount);
        p.claimed = uint128(uint256(p.claimed) - movedClaimed);

        newId = nextId++;
        _positions[newId] = Position({
            token: p.token,
            start: p.start,
            cliff: p.cliff,
            end: p.end,
            amount: uint128(amount),
            claimed: uint128(movedClaimed)
        });
        _safeMint(to, newId);

        emit Split(id, newId, amount);
    }

    // ---------------------------------------------------------------------
    // Claiming
    // ---------------------------------------------------------------------

    /**
     * @notice Claim everything currently claimable on a position. Callable by
     *         the position owner or an approved operator; funds always go to
     *         the position owner.
     */
    function claim(uint256 id) external nonReentrant returns (uint256 amount) {
        address positionOwner = _requireOwned(id);
        if (positionOwner != msg.sender && !isApprovedForAll(positionOwner, msg.sender) && getApproved(id) != msg.sender)
        {
            revert NotPositionOwner();
        }

        Position storage p = _positions[id];
        amount = _claimableOf(p);
        if (amount == 0) revert NothingToClaim();

        p.claimed += uint128(amount);
        totalLocked[p.token] -= amount;

        address token = p.token;
        // Burn fully-claimed, fully-vested positions to keep wallets tidy.
        if (p.claimed == p.amount && block.timestamp >= p.end) {
            delete _positions[id];
            _burn(id);
        }

        _payout(token, positionOwner, amount);
        emit Claimed(id, token, positionOwner, amount);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Full position data.
    function getPosition(uint256 id) external view returns (Position memory) {
        _requireOwned(id);
        return _positions[id];
    }

    /// @notice Amount claimable right now.
    function claimable(uint256 id) external view returns (uint256) {
        if (_ownerOf(id) == address(0)) return 0;
        return _claimableOf(_positions[id]);
    }

    /// @notice Amount vested at timestamp `t` (claimed or not).
    function vestedAmount(uint256 id, uint48 t) public view returns (uint256) {
        return _vested(_positions[id], t);
    }

    /// @notice All position ids owned by `account`. O(n) — intended for
    ///         off-chain callers (frontends, bots, agents), not other contracts.
    function positionsOf(address account) external view returns (uint256[] memory ids) {
        uint256 n = balanceOf(account);
        ids = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            ids[i] = tokenOfOwnerByIndex(account, i);
        }
    }

    // ---------------------------------------------------------------------
    // Admin — deliberately minimal
    // ---------------------------------------------------------------------

    /// @notice Set the protocol fee. Hard-capped at `MAX_FEE_BPS`.
    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    /// @notice Set the fee recipient.
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    /// @notice Pause creation of new locks and top-ups. Claims are NEVER pausable.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume creation of new locks.
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sweep surplus balance (tokens sent directly to the vault by
     *         mistake, or ETH force-sent) to the fee recipient. Can never touch
     *         funds backing positions: only `balance - totalLocked` is sweepable.
     */
    function sweep(address token) external nonReentrant {
        uint256 balance =
            token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 surplus = balance - totalLocked[token];
        if (surplus == 0) revert ZeroAmount();
        _payout(token, feeRecipient, surplus);
        emit Swept(token, feeRecipient, surplus);
    }

    // ---------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------

    /// @inheritdoc ERC721
    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        Position memory p = _positions[id];

        (string memory symbol_, uint8 decimals_) = _tokenMeta(p.token);
        string memory amountStr = _formatAmount(p.amount, decimals_);
        string memory unlockStr = uint256(p.end).toString();

        string memory svg = _renderSVG(symbol_, amountStr, p);

        string memory json = string.concat(
            '{"name":"Lock #',
            id.toString(),
            " \\u2014 ",
            amountStr,
            " ",
            symbol_,
            '","description":"A LockVault position. The locked balance is claimable by the owner of this NFT once vested.","attributes":[',
            '{"trait_type":"Token","value":"',
            p.token == address(0) ? "ETH" : p.token.toHexString(),
            '"},{"trait_type":"Symbol","value":"',
            symbol_,
            '"},{"display_type":"date","trait_type":"Unlocks","value":',
            unlockStr,
            '},{"trait_type":"Vesting","value":"',
            p.start == p.end ? "Time-lock" : "Linear",
            '"}],"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _lock(LockParams memory params, uint256 value) private returns (uint256 id) {
        if (params.beneficiary == address(0)) revert ZeroAddress();
        if (params.start > params.cliff || params.cliff > params.end) revert InvalidSchedule();
        if (params.end <= block.timestamp) revert InvalidSchedule();
        if (uint256(params.end) > block.timestamp + MAX_DURATION) revert DurationTooLong();

        (uint256 net, uint256 fee) = _collect(params.token, params.amount, value);

        id = nextId++;
        _positions[id] = Position({
            token: params.token,
            start: params.start,
            cliff: params.cliff,
            end: params.end,
            amount: uint128(net),
            claimed: 0
        });
        totalLocked[params.token] += net;
        _safeMint(params.beneficiary, id);

        emit Locked(
            id, params.token, params.beneficiary, msg.sender, net, fee, params.start, params.cliff, params.end
        );
    }

    /**
     * @dev Pull `amount` of `token` from the caller, take the protocol fee, and
     *      return the net amount credited to the position. Measures balance
     *      deltas so fee-on-transfer tokens are recorded correctly.
     */
    function _collect(address token, uint256 amount, uint256 value)
        private
        returns (uint256 net, uint256 fee)
    {
        if (amount == 0) revert ZeroAmount();
        uint256 received;

        if (token == address(0)) {
            if (value != amount) revert WrongMsgValue();
            received = amount;
        } else {
            if (value != 0) revert WrongMsgValue();
            uint256 before = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            received = IERC20(token).balanceOf(address(this)) - before;
        }

        fee = (received * feeBps) / BPS_DENOMINATOR;
        net = received - fee;
        if (net == 0) revert ZeroAmount();
        if (net > type(uint128).max) revert AmountTooLarge();

        if (fee > 0) {
            _payout(token, feeRecipient, fee);
        }
    }

    function _payout(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert EthTransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _vested(Position memory p, uint256 t) private pure returns (uint256) {
        if (t < p.cliff || p.end == 0) return 0;
        if (t >= p.end) return p.amount;
        // p.start < p.end here, since t >= cliff >= start and t < end.
        return (uint256(p.amount) * (t - p.start)) / (p.end - p.start);
    }

    function _claimableOf(Position memory p) private view returns (uint256) {
        uint256 vested = _vested(p, block.timestamp);
        // Saturating: `claimed` can briefly exceed `vested` after an extend()
        // re-stretches an in-progress vesting schedule, or by 1 wei of
        // split() rounding. Never underflow — worst case claimable is 0.
        return vested > p.claimed ? vested - p.claimed : 0;
    }

    function _tokenMeta(address token) private view returns (string memory symbol_, uint8 decimals_) {
        if (token == address(0)) return ("ETH", 18);
        symbol_ = "TOKEN";
        decimals_ = 18;
        try IERC20Metadata(token).symbol() returns (string memory s) {
            if (bytes(s).length != 0 && bytes(s).length <= 12) symbol_ = s;
        } catch {}
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            decimals_ = d;
        } catch {}
    }

    function _formatAmount(uint256 amount, uint8 decimals_) private pure returns (string memory) {
        uint256 unit = 10 ** decimals_;
        uint256 whole = amount / unit;
        // two decimal places
        uint256 frac = decimals_ >= 2 ? (amount % unit) / (unit / 100) : 0;
        return string.concat(
            whole.toString(), ".", frac < 10 ? string.concat("0", frac.toString()) : frac.toString()
        );
    }

    function _renderSVG(string memory symbol_, string memory amountStr, Position memory p)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">',
            '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">',
            '<stop offset="0" stop-color="#0f172a"/><stop offset="1" stop-color="#1e1b4b"/></linearGradient></defs>',
            '<rect width="400" height="400" rx="24" fill="url(#g)"/>',
            '<text x="32" y="60" font-family="monospace" font-size="14" fill="#818cf8" letter-spacing="4">LOCKVAULT</text>',
            '<text x="32" y="200" font-family="monospace" font-size="34" font-weight="bold" fill="#f8fafc">',
            amountStr,
            " ",
            symbol_,
            "</text>",
            '<text x="32" y="240" font-family="monospace" font-size="14" fill="#94a3b8">',
            p.start == p.end ? "time-lock until" : "vesting until",
            "</text>",
            '<text x="32" y="264" font-family="monospace" font-size="16" fill="#e2e8f0">t=',
            uint256(p.end).toString(),
            "</text>",
            '<text x="32" y="360" font-family="monospace" font-size="12" fill="#64748b">lock.finance</text>',
            "</svg>"
        );
    }

    // ---------------------------------------------------------------------
    // ERC-165 / ERC-721 plumbing
    // ---------------------------------------------------------------------

    /// @dev Reject stray ETH — deposits must go through lock/topUp. Surplus
    ///      force-sent ETH is recoverable via `sweep`.
    receive() external payable {
        revert WrongMsgValue();
    }
}
