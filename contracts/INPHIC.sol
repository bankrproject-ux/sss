// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IIdentityResolver {
    function identityOf(address user) external view returns (uint256);
}

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPancakePair {
    function mint(address to) external returns (uint256 liquidity);
}

interface IWBNB {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

contract INPHIC {
    // BNB Chain Mainnet
    address public constant WBNB =
        0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    address public constant DEAD =
        0x000000000000000000000000000000000000dEaD;

    // ERC20
    string public constant name = "INPHIC";
    string public constant symbol = "INPHIC";
    uint8 public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 500_000_000 ether;

    // Shares
    uint256 public constant MAX_SHARES = 3500;
    uint256 public constant FREE_SHARES = 1500;
    uint256 public constant PAID_SHARES = 2000;
    uint256 public constant TOKENS_PER_SHARE = 100_000 ether;

    // Allocation
    uint256 public constant LP_ALLOCATION = 80_000_000 ether;
    uint256 public constant TEAM_ALLOCATION = 50_000_000 ether;
    uint256 public constant COMMUNITY_ALLOCATION = 20_000_000 ether;

    // Mint pricing
    uint256 public constant FIRST_TIER_SHARES = 10;
    uint256 public constant FIRST_TIER_PRICE = 0.0005 ether;
    uint256 public constant SECOND_TIER_PRICE = 0.001 ether;

    // Fees
    uint256 public constant REFUND_WINDOW = 24 hours;
    uint256 public constant REFUND_BPS = 8000;
    uint256 public constant LIQUIDITY_BPS = 8000;
    uint256 public constant BUY_TAX_BPS = 300;
    uint256 public constant SELL_TAX_BPS = 300;

    address public immutable owner;
    address payable public immutable treasury;
    IIdentityResolver public immutable identityResolver;

    uint256 public totalSupply = TOTAL_SUPPLY;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // 1 = Minting
    // 2 = Launch pending
    // 3 = Launched
    // 4 = Sale withdrawn
    uint8 public phase = 1;

    bool public paused;
    address public pair;

    uint256 public paidSharesSold;
    uint256 public freeSharesClaimed;
    uint256 public totalRaised;

    mapping(uint256 => uint256) public paidEverById;
    mapping(uint256 => bool) public freeClaimedById;

    struct Deposit {
        address buyer;
        uint256 amount;
        uint256 timestamp;
        uint256 shares;
        uint256 agentId;
        bool refunded;
        bool settled;
    }

    Deposit[] private deposits;

    mapping(address => uint256[]) private buyerDepositIds;

    bool private entered;

    modifier nonReentrant() {
        require(!entered, "REENTRANCY");
        entered = true;
        _;
        entered = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 value);

    event FreeClaimed(address indexed user, uint256 indexed agentId);

    event Minted(
        address indexed user,
        uint256 indexed agentId,
        uint256 shares,
        uint256 cost,
        uint256 depositId
    );

    event Refunded(
        address indexed user,
        uint256 indexed depositId,
        uint256 amount
    );

    event LaunchPending();

    event PoolOpened(
        address indexed pair,
        uint256 bnbLiquidity,
        uint256 tokenLiquidity,
        uint256 treasuryAmount
    );

    event SaleWithdrawn(uint256 amount);
    event PhaseChanged(uint8 phase);

    constructor(
        address _identityResolver,
        address payable _treasury
    ) {
        require(_identityResolver != address(0), "ZERO_RESOLVER");
        require(_treasury != address(0), "ZERO_TREASURY");

        owner = msg.sender;
        treasury = _treasury;
        identityResolver = IIdentityResolver(_identityResolver);

        uint256 publicAllocation =
            MAX_SHARES * TOKENS_PER_SHARE;

        require(
            publicAllocation +
            LP_ALLOCATION +
            TEAM_ALLOCATION +
            COMMUNITY_ALLOCATION == TOTAL_SUPPLY,
            "SUPPLY_MISMATCH"
        );

        balanceOf[address(this)] =
            publicAllocation + LP_ALLOCATION;

        balanceOf[treasury] =
            TEAM_ALLOCATION + COMMUNITY_ALLOCATION;

        emit Transfer(
            address(0),
            address(this),
            publicAllocation + LP_ALLOCATION
        );

        emit Transfer(
            address(0),
            treasury,
            TEAM_ALLOCATION + COMMUNITY_ALLOCATION
        );

        emit PhaseChanged(1);
    }

    // --------------------------------------------------
    // VIEWS
    // --------------------------------------------------

    function totalSoldShares() public view returns (uint256) {
        return paidSharesSold + freeSharesClaimed;
    }

    function depositCount() external view returns (uint256) {
        return deposits.length;
    }

    function getDeposit(
        uint256 depositId
    ) external view returns (Deposit memory) {
        require(depositId < deposits.length, "BAD_DEPOSIT_ID");
        return deposits[depositId];
    }

    function buyerDepositCount(
        address buyer
    ) external view returns (uint256) {
        return buyerDepositIds[buyer].length;
    }

    function getBuyerDepositId(
        address buyer,
        uint256 index
    ) external view returns (uint256) {
        return buyerDepositIds[buyer][index];
    }

    function quoteMint(
        uint256 requested,
        uint256 alreadyPaid
    ) public pure returns (uint256) {
        require(requested > 0, "BAD_QUANTITY");

        uint256 firstRemaining =
            alreadyPaid >= FIRST_TIER_SHARES
                ? 0
                : FIRST_TIER_SHARES - alreadyPaid;

        uint256 firstCount =
            requested < firstRemaining
                ? requested
                : firstRemaining;

        uint256 secondCount = requested - firstCount;

        return
            (firstCount * FIRST_TIER_PRICE) +
            (secondCount * SECOND_TIER_PRICE);
    }

    function userInfo(
        address user
    ) external view returns (
        uint256 agentId,
        uint256 paidSharesEver,
        uint256 remainingFirstTier,
        bool freeClaimed,
        uint256 userDeposits
    ) {
        agentId = identityResolver.identityOf(user);

        paidSharesEver =
            agentId == 0 ? 0 : paidEverById[agentId];

        remainingFirstTier =
            paidSharesEver >= FIRST_TIER_SHARES
                ? 0
                : FIRST_TIER_SHARES - paidSharesEver;

        freeClaimed =
            agentId != 0 && freeClaimedById[agentId];

        userDeposits = buyerDepositIds[user].length;
    }

    // --------------------------------------------------
    // FREE CLAIM
    // --------------------------------------------------

    function claimFree() external nonReentrant {
        require(!paused, "PAUSED");
        require(phase == 1, "WRONG_PHASE");
        require(freeSharesClaimed < FREE_SHARES, "FREE_SOLD_OUT");
        require(totalSoldShares() < MAX_SHARES, "SOLD_OUT");

        uint256 id = identityResolver.identityOf(msg.sender);

        require(id != 0, "NO_AGENT_ID");
        require(!freeClaimedById[id], "ALREADY_CLAIMED");

        freeClaimedById[id] = true;
        freeSharesClaimed++;

        _move(address(this), msg.sender, TOKENS_PER_SHARE);

        emit FreeClaimed(msg.sender, id);

        _checkSoldOut();
    }

    // --------------------------------------------------
    // PAID MINT
    // --------------------------------------------------

    function mint(uint256 requested)
        external
        payable
        nonReentrant
    {
        require(!paused, "PAUSED");
        require(phase == 1, "WRONG_PHASE");
        require(requested > 0, "BAD_QUANTITY");

        require(
            paidSharesSold + requested <= PAID_SHARES,
            "PAID_SOLD_OUT"
        );

        require(
            totalSoldShares() + requested <= MAX_SHARES,
            "SOLD_OUT"
        );

        uint256 id = identityResolver.identityOf(msg.sender);
        require(id != 0, "NO_AGENT_ID");

        uint256 cost = quoteMint(
            requested,
            paidEverById[id]
        );

        require(msg.value == cost, "INCORRECT_BNB");

        paidEverById[id] += requested;
        paidSharesSold += requested;
        totalRaised += cost;

        uint256 depositId = deposits.length;

        deposits.push(
            Deposit({
                buyer: msg.sender,
                amount: cost,
                timestamp: block.timestamp,
                shares: requested,
                agentId: id,
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

        emit Minted(msg.sender, id, requested, cost, depositId);

        _checkSoldOut();
    }

    // --------------------------------------------------
    // REFUND
    // --------------------------------------------------

    function refundDeposit(uint256 depositId)
        external
        nonReentrant
    {
        require(phase == 1, "REFUND_CLOSED");
        require(depositId < deposits.length, "BAD_DEPOSIT_ID");

        Deposit storage d = deposits[depositId];

        require(d.buyer == msg.sender, "NOT_BUYER");
        require(!d.refunded && !d.settled, "ALREADY_SETTLED");

        require(
            block.timestamp < d.timestamp + REFUND_WINDOW,
            "REFUND_EXPIRED"
        );

        uint256 refundAmount =
            (d.amount * REFUND_BPS) / 10_000;

        uint256 treasuryPart = d.amount - refundAmount;

        uint256 tokenAmount =
            d.shares * TOKENS_PER_SHARE;

        require(
            balanceOf[msg.sender] >= tokenAmount,
            "TOKENS_MOVED"
        );

        d.refunded = true;
        d.settled = true;

        paidSharesSold -= d.shares;
        totalRaised -= d.amount;

        _move(msg.sender, address(this), tokenAmount);

        if (treasuryPart > 0) {
            (bool treasuryOk, ) =
                treasury.call{value: treasuryPart}("");

            require(treasuryOk, "TREASURY_TRANSFER_FAILED");
        }

        (bool ok, ) =
            msg.sender.call{value: refundAmount}("");

        require(ok, "REFUND_TRANSFER_FAILED");

        emit Refunded(msg.sender, depositId, refundAmount);
    }

    // --------------------------------------------------
    // WITHDRAW RESIDUE
    // --------------------------------------------------

    function withdrawResidue()
        external
        onlyOwner
        nonReentrant
    {
        require(phase == 1, "WRONG_PHASE");

        // Stop mint and close all refund claims.
        phase = 4;
        emit PhaseChanged(4);

        // Sweep the entire native BNB balance.
        uint256 amount = address(this).balance;

        require(amount > 0, "NO_BNB_BALANCE");

        (bool ok, ) = treasury.call{value: amount}("");

        require(ok, "TREASURY_TRANSFER_FAILED");

        emit SaleWithdrawn(amount);
    }

    // --------------------------------------------------
    // AUTO LAUNCH
    // --------------------------------------------------

    function _checkSoldOut() internal {
        if (totalSoldShares() == MAX_SHARES) {
            phase = 2;

            emit PhaseChanged(2);
            emit LaunchPending();

            // Failed auto-launch does not revert mint.
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

    function _launch() internal {
        uint256 bnbBalance = address(this).balance;

        require(bnbBalance > 0, "NO_BNB_RAISED");

        require(
            balanceOf[address(this)] >= LP_ALLOCATION,
            "LP_TOKENS_MISSING"
        );

        address lpPair =
            IPancakeFactory(PANCAKE_FACTORY).getPair(
                address(this),
                WBNB
            );

        if (lpPair == address(0)) {
            lpPair =
                IPancakeFactory(PANCAKE_FACTORY).createPair(
                    address(this),
                    WBNB
                );
        }

        require(lpPair != address(0), "PAIR_CREATION_FAILED");

        uint256 bnbForLiquidity =
            (bnbBalance * LIQUIDITY_BPS) / 10_000;

        uint256 bnbForTreasury =
            bnbBalance - bnbForLiquidity;

        phase = 3;
        pair = lpPair;

        emit PhaseChanged(3);

        IWBNB(WBNB).deposit{value: bnbForLiquidity}();

        require(
            IWBNB(WBNB).transfer(lpPair, bnbForLiquidity),
            "WBNB_TRANSFER_FAILED"
        );

        // Fixed LP token allocation.
        _move(address(this), lpPair, LP_ALLOCATION);

        // LP receipt sent to dead address.
        IPancakePair(lpPair).mint(DEAD);

        if (bnbForTreasury > 0) {
            (bool ok, ) =
                treasury.call{value: bnbForTreasury}("");

            require(ok, "TREASURY_TRANSFER_FAILED");
        }

        emit PoolOpened(
            lpPair,
            bnbForLiquidity,
            LP_ALLOCATION,
            bnbForTreasury
        );
    }

    // --------------------------------------------------
    // ADMIN
    // --------------------------------------------------

    function setPaused(bool value) external onlyOwner {
        paused = value;
    }

    // --------------------------------------------------
    // ERC20
    // --------------------------------------------------

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
    }

    function _move(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(to != address(0), "ZERO_ADDRESS");
        require(balanceOf[from] >= amount, "BALANCE");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    receive() external payable {
        revert("USE_PAID_MINT");
    }
}
