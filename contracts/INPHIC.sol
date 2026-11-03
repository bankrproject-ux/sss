
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ======================================================
// AGENT ID GATE
// ======================================================

interface IAgentIDGate {
    function balanceOf(address account) external view returns (uint256);
}

// ======================================================
// PANCAKESWAP V2
// ======================================================

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPancakePair {
    function mint(address to) external returns (uint256 liquidity);
}

interface IWBNB {
    function deposit() external payable;
    function transfer(address to, uint256 amount) external returns (bool);
}

// ======================================================
// INPHIC
// ======================================================

contract INPHIC {
    // BNB Chain Mainnet
    address public constant AGENT_ID_GATE =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    address public constant WBNB =
        0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    address public constant DEAD =
        0x000000000000000000000000000000000000dEaD;

    string public constant name = "INPHIC";
    string public constant symbol = "INPHIC";
    uint8 public constant decimals = 18;

    // ==================================================
    // TOKENOMICS
    // ==================================================

    uint256 public constant TOTAL_SUPPLY = 500_000_000 ether;

    uint256 public constant MAX_SHARES = 3_500;
    uint256 public constant FREE_SHARES = 1_500;
    uint256 public constant PAID_SHARES = 2_000;

    uint256 public constant TOKENS_PER_SHARE = 100_000 ether;

    uint256 public constant LP_ALLOCATION = 80_000_000 ether;
    uint256 public constant TEAM_ALLOCATION = 50_000_000 ether;
    uint256 public constant COMMUNITY_ALLOCATION = 20_000_000 ether;

    uint256 public constant FIRST_TIER_SHARES = 10;
    uint256 public constant FIRST_TIER_PRICE = 0.0005 ether;
    uint256 public constant SECOND_TIER_PRICE = 0.001 ether;

    uint256 public constant REFUND_WINDOW = 24 hours;
    uint256 public constant REFUND_BPS = 8_000;

    uint256 public constant LIQUIDITY_BPS = 8_000;

    uint256 public constant BUY_TAX_BPS = 300;
    uint256 public constant SELL_TAX_BPS = 300;

    // ==================================================
    // STATE
    // ==================================================

    address public immutable owner;
    address payable public immutable treasury;

    uint256 public totalSupply = TOTAL_SUPPLY;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // 1 = minting
    // 2 = sold out / launch pending
    // 3 = launched
    // 4 = sale withdrawn

    uint8 public phase = 1;
    bool public paused;
    address public pair;

    uint256 public paidSharesSold;
    uint256 public freeSharesClaimed;
    uint256 public totalRaised;

    // Wallet is the identity key.
    // Agent ID NFT is assumed to be non-transferable.
    mapping(address => bool) public freeClaimedByWallet;
    mapping(address => uint256) public paidByWallet;

    struct Deposit {
        address buyer;
        uint256 amount;
        uint256 timestamp;
        uint256 shares;
        bool refunded;
        bool settled;
    }

    Deposit[] private deposits;

    mapping(address => uint256[]) private buyerDepositIds;

    bool private entered;

    // ==================================================
    // MODIFIERS
    // ==================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    modifier nonReentrant() {
        require(!entered, "REENTRANCY");
        entered = true;
        _;
        entered = false;
    }

    // ==================================================
    // EVENTS
    // ==================================================

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event FreeClaimed(address indexed user);
    event Minted(address indexed user, uint256 shares, uint256 paid);

    event DepositRefunded(
        address indexed user,
        uint256 indexed depositId,
        uint256 amount
    );

    event PoolOpened(
        address indexed pair,
        uint256 bnbLiquidity,
        uint256 tokenLiquidity,
        uint256 treasuryAmount
    );

    event ResidueWithdrawn(uint256 amount);
    event LaunchPending();

    // ==================================================
    // CONSTRUCTOR
    // ==================================================

    constructor(address payable _treasury) {
        require(_treasury != address(0), "ZERO_TREASURY");

        owner = msg.sender;
        treasury = _treasury;

        // 350M public + 80M LP
        balanceOf[address(this)] =
            (MAX_SHARES * TOKENS_PER_SHARE) + LP_ALLOCATION;

        // 50M team + 20M community
        balanceOf[treasury] =
            TEAM_ALLOCATION + COMMUNITY_ALLOCATION;

        emit Transfer(
            address(0),
            address(this),
            balanceOf[address(this)]
        );

        emit Transfer(
            address(0),
            treasury,
            balanceOf[treasury]
        );
    }

    // ==================================================
    // AGENT ID GATE
    // ==================================================

    function hasAgentID(address wallet) public view returns (bool) {
        return IAgentIDGate(AGENT_ID_GATE).balanceOf(wallet) > 0;
    }

    function checkAgentID(address wallet) external view returns (bool) {
        return hasAgentID(wallet);
    }

    function _requireAgentID(address wallet) internal view {
        require(hasAgentID(wallet), "NO_AGENT_ID");
    }

    // ==================================================
    // INFORMATION
    // ==================================================

    function totalSoldShares() public view returns (uint256) {
        return paidSharesSold + freeSharesClaimed;
    }

    function depositCount() external view returns (uint256) {
        return deposits.length;
    }

    function getDeposit(uint256 id)
        external
        view
        returns (Deposit memory)
    {
        return deposits[id];
    }

    function getBuyerDepositId(address buyer, uint256 index)
        external
        view
        returns (uint256)
    {
        return buyerDepositIds[buyer][index];
    }

    function buyerDepositCount(address buyer)
        external
        view
        returns (uint256)
    {
        return buyerDepositIds[buyer].length;
    }

    function userInfo(address user)
        external
        view
        returns (
            bool validAgentID,
            uint256 paidShares,
            uint256 remainingToFirstTier,
            bool freeClaimed,
            uint256 userDepositCount
        )
    {
        validAgentID = hasAgentID(user);

        paidShares = paidByWallet[user];

        remainingToFirstTier =
            paidShares >= FIRST_TIER_SHARES
                ? 0
                : FIRST_TIER_SHARES - paidShares;

        freeClaimed = freeClaimedByWallet[user];
        userDepositCount = buyerDepositIds[user].length;
    }

    // ==================================================
    // PRICING
    // ==================================================

    function quoteMint(
        uint256 requested,
        uint256 alreadyPaid
    ) public pure returns (uint256 cost) {
        require(requested > 0, "BAD_QUANTITY");

        uint256 remaining =
            alreadyPaid >= FIRST_TIER_SHARES
                ? 0
                : FIRST_TIER_SHARES - alreadyPaid;

        uint256 firstCount =
            requested < remaining ? requested : remaining;

        uint256 secondCount = requested - firstCount;

        cost =
            (firstCount * FIRST_TIER_PRICE) +
            (secondCount * SECOND_TIER_PRICE);
    }

    function quoteMintFor(address wallet, uint256 requested)
        external
        view
        returns (uint256)
    {
        _requireAgentID(wallet);

        return quoteMint(
            requested,
            paidByWallet[wallet]
        );
    }

    // ==================================================
    // FREE MINT
    // ==================================================

    function claimFree() external nonReentrant {
        require(!paused, "PAUSED");
        require(phase == 1, "WRONG_PHASE");
        require(freeSharesClaimed < FREE_SHARES, "FREE_SOLD_OUT");

        _requireAgentID(msg.sender);

        require(
            !freeClaimedByWallet[msg.sender],
            "ALREADY_CLAIMED"
        );

        freeClaimedByWallet[msg.sender] = true;
        freeSharesClaimed++;

        _move(
            address(this),
            msg.sender,
            TOKENS_PER_SHARE
        );

        emit FreeClaimed(msg.sender);

        _checkSoldOut();
    }

    // ==================================================
    // PAID MINT
    // ==================================================

    function mint(uint256 requested)
        external
        payable
        nonReentrant
    {
        require(!paused, "PAUSED");
        require(phase == 1, "WRONG_PHASE");
        require(requested > 0, "BAD_QUANTITY");

        _requireAgentID(msg.sender);

        require(
            totalSoldShares() + requested <= MAX_SHARES,
            "SOLD_OUT"
        );

        require(
            paidSharesSold + requested <= PAID_SHARES,
            "PAID_SOLD_OUT"
        );

        uint256 cost = quoteMint(
            requested,
            paidByWallet[msg.sender]
        );

        require(msg.value == cost, "INCORRECT_BNB");

        paidByWallet[msg.sender] += requested;
        paidSharesSold += requested;
        totalRaised += cost;

        uint256 depositId = deposits.length;

        deposits.push(
            Deposit({
                buyer: msg.sender,
                amount: cost,
                timestamp: block.timestamp,
                shares: requested,
                refunded: false,
                settled: false
            })
        );

        buyerDepositIds[msg.sender].push(depositId);

        _move(
            address(this),
            msg.sender,
            requested * TOKENS_PER_SHARE
        );

        emit Minted(msg.sender, requested, cost);

        _checkSoldOut();
    }

    // ==================================================
    // REFUND
    // ==================================================

    function refundDeposit(uint256 depositId)
        external
        nonReentrant
    {
        require(phase == 1, "REFUND_CLOSED");

        require(depositId < deposits.length, "INVALID_DEPOSIT");

        Deposit storage d = deposits[depositId];

        require(d.buyer == msg.sender, "NOT_BUYER");
        require(!d.refunded && !d.settled, "ALREADY_SETTLED");

        require(
            block.timestamp < d.timestamp + REFUND_WINDOW,
            "REFUND_EXPIRED"
        );

        uint256 refundAmount =
            (d.amount * REFUND_BPS) / 10_000;

        uint256 treasuryPart =
            d.amount - refundAmount;

        uint256 tokenAmount =
            d.shares * TOKENS_PER_SHARE;

        require(
            balanceOf[msg.sender] >= tokenAmount,
            "TOKENS_MOVED"
        );

        d.refunded = true;
        d.settled = true;

        // Price tier remains cumulative after refund.
        paidSharesSold -= d.shares;
        totalRaised -= d.amount;

        _move(
            msg.sender,
            address(this),
            tokenAmount
        );

        if (treasuryPart > 0) {
            (bool treasuryOk, ) =
                treasury.call{value: treasuryPart}("");

            require(treasuryOk, "TREASURY_TRANSFER_FAILED");
        }

        (bool ok, ) =
            msg.sender.call{value: refundAmount}("");

        require(ok, "REFUND_TRANSFER_FAILED");

        emit DepositRefunded(
            msg.sender,
            depositId,
            refundAmount
        );
    }

    // ==================================================
    // WITHDRAW RESIDUE
    // ==================================================

    // Owner stops the sale and sends the entire BNB balance
    // to treasury. All refund rights close after this call.

    function withdrawResidue()
        external
        onlyOwner
        nonReentrant
    {
        require(phase == 1, "WRONG_PHASE");

        phase = 4;

        uint256 amount = address(this).balance;

        require(amount > 0, "NO_BNB_BALANCE");

        (bool ok, ) =
            treasury.call{value: amount}("");

        require(ok, "TREASURY_TRANSFER_FAILED");

        emit ResidueWithdrawn(amount);
    }

    // ==================================================
    // AUTOMATIC LAUNCH
    // ==================================================

    function _checkSoldOut() internal {
        if (totalSoldShares() == MAX_SHARES) {
            phase = 2;

            emit LaunchPending();

            try this.autoLaunch() {} catch {}
        }
    }

    function autoLaunch() external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(phase == 2, "WRONG_PHASE");

        _launch();
    }

    function launch() external onlyOwner nonReentrant {
        require(phase == 2, "LAUNCH_NOT_PENDING");

        _launch();
    }

    // ==================================================
    // PANCAKESWAP LAUNCH
    // ==================================================

    function _launch() internal {
        uint256 currentBalance = address(this).balance;

        uint256 bnbForLiquidity =
            (currentBalance * LIQUIDITY_BPS) / 10_000;

        uint256 bnbForTreasury =
            currentBalance - bnbForLiquidity;

        require(
            balanceOf[address(this)] >= LP_ALLOCATION,
            "LP_TOKENS_MISSING"
        );

        address currentPair =
            IPancakeFactory(PANCAKE_FACTORY).getPair(
                address(this),
                WBNB
            );

        if (currentPair == address(0)) {
            currentPair =
                IPancakeFactory(PANCAKE_FACTORY).createPair(
                    address(this),
                    WBNB
                );
        }

        pair = currentPair;
        phase = 3;

        IWBNB(WBNB).deposit{value: bnbForLiquidity}();

        require(
            IWBNB(WBNB).transfer(
                currentPair,
                bnbForLiquidity
            ),
            "WBNB_TRANSFER_FAILED"
        );

        _move(
            address(this),
            currentPair,
            LP_ALLOCATION
        );

        IPancakePair(currentPair).mint(DEAD);

        if (bnbForTreasury > 0) {
            (bool ok, ) =
                treasury.call{value: bnbForTreasury}("");

            require(ok, "TREASURY_TRANSFER_FAILED");
        }

        emit PoolOpened(
            currentPair,
            bnbForLiquidity,
            LP_ALLOCATION,
            bnbForTreasury
        );
    }

    // ==================================================
    // OWNER CONTROLS
    // ==================================================

    function setPaused(bool value) external onlyOwner {
        paused = value;
    }

    // ==================================================
    // ERC20
    // ==================================================

    function transfer(address to, uint256 amount)
        external
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        external
        returns (bool)
    {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        require(allowed >= amount, "ALLOWANCE");

        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }

        _transfer(from, to, amount);

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(phase == 3, "TRADING_LOCKED");
        require(to != address(0), "ZERO_ADDRESS");
        require(balanceOf[from] >= amount, "BALANCE");

        uint256 tax;

        bool exempt =
            from == treasury ||
            to == treasury ||
            from == address(this) ||
            to == address(this);

        if (!exempt && pair != address(0)) {
            if (from == pair) {
                tax = (amount * BUY_TAX_BPS) / 10_000;
            } else if (to == pair) {
                tax = (amount * SELL_TAX_BPS) / 10_000;
            }
        }

        balanceOf[from] -= amount;

        if (tax > 0) {
            balanceOf[treasury] += tax;
            emit Transfer(from, treasury, tax);
        }

        balanceOf[to] += amount - tax;

        emit Transfer(from, to, amount - tax);

        return;
    }

    function _move(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(balanceOf[from] >= amount, "BALANCE");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    receive() external payable {}
}
