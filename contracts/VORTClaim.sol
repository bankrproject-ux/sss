
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VORTClaim is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant REWARD_PER_NFT = 50_000 ether;
    uint256 public constant CLAIM_FEE = 0.0002 ether;
    uint256 public constant MAX_ALLOCATION = 444_400_000 ether;
    uint256 public constant MAX_NFT_SUPPLY = 8888;

    IERC721 public immutable nftContract;
    IERC20 public immutable tokenContract;
    address payable public immutable feeRecipient;

    mapping(uint256 => bool) public claimed;

    uint256 public totalClaimedNFTs;
    uint256 public totalTokensClaimed;

    event Claimed(
        address indexed account,
        uint256 indexed tokenId,
        uint256 reward
    );

    event ClaimFeePaid(
        address indexed account,
        uint256 quantity,
        uint256 amount
    );

   
constructor() {
    nftContract = IERC721(
        0xb8a529F9bB1EEd3dEf2F5178678C447C646D034B
    );

    tokenContract = IERC20(
        0x8629f95Ef3C0Ea98CB1944964e640A9Cc135C889
    );

    feeRecipient = payable(
        0x50D5247deFa13922C89a6276D725844b905FA73b
    );
}

    function claim(
        uint256[] calldata tokenIds
    ) external payable nonReentrant {
        uint256 quantity = tokenIds.length;

        require(quantity > 0, "Empty token IDs");
        require(quantity <= MAX_NFT_SUPPLY, "Quantity too large");

        uint256 requiredFee = quantity * CLAIM_FEE;
        uint256 totalReward = quantity * REWARD_PER_NFT;

        require(msg.value == requiredFee, "Incorrect BNB fee");

        require(
            totalTokensClaimed + totalReward <= MAX_ALLOCATION,
            "Claim allocation exhausted"
        );

        // Verify ownership and prevent duplicate claims.
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = tokenIds[i];

            require(
                tokenId > 0 && tokenId <= MAX_NFT_SUPPLY,
                "Invalid token ID"
            );

            require(
                nftContract.ownerOf(tokenId) == msg.sender,
                "Not NFT owner"
            );

            require(
                !claimed[tokenId],
                "NFT already claimed"
            );

            claimed[tokenId] = true;
        }

        totalClaimedNFTs += quantity;
        totalTokensClaimed += totalReward;

        // Transfer VORT tokens to the calling wallet.
        tokenContract.safeTransfer(msg.sender, totalReward);

        // Forward the claim fee.
        (bool success, ) = feeRecipient.call{value: requiredFee}("");
        require(success, "Fee transfer failed");

        for (uint256 i = 0; i < quantity; i++) {
            emit Claimed(
                msg.sender,
                tokenIds[i],
                REWARD_PER_NFT
            );
        }

        emit ClaimFeePaid(msg.sender, quantity, requiredFee);
    }

    function isClaimed(
        uint256 tokenId
    ) external view returns (bool) {
        return claimed[tokenId];
    }

    function getClaimFee(
        uint256 quantity
    ) external pure returns (uint256) {
        return quantity * CLAIM_FEE;
    }

    function getClaimReward(
        uint256 quantity
    ) external pure returns (uint256) {
        return quantity * REWARD_PER_NFT;
    }

    function remainingAllocation()
        external
        view
        returns (uint256)
    {
        return MAX_ALLOCATION - totalTokensClaimed;
    }
}
