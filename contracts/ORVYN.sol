
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract ORVYN is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 5_000;
    uint256 public constant MAX_PER_WALLET = 5;

    uint256 public constant FIRST_MINT_PRICE = 0;
    uint256 public constant NEXT_MINT_PRICE = 0.0005 ether;

    address public constant AGENT_ID_CONTRACT =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    uint256 public totalMinted;

    mapping(address => uint256) public mintedByWallet;
    mapping(uint256 => uint8) public imageIndex;

    event Minted(
        address indexed account,
        uint256 indexed tokenId,
        uint8 image
    );

    event ProceedsForwarded(address indexed owner, uint256 amount);

    constructor(address ownerWallet)
        ERC721("ORVYN", "ORVYN")
        Ownable(ownerWallet)
    {
        require(ownerWallet != address(0), "Invalid owner");
    }

    function mint(uint256 quantity) external payable nonReentrant {
        require(quantity > 0, "Quantity is zero");

        require(
            IERC721(AGENT_ID_CONTRACT).balanceOf(msg.sender) > 0,
            "Agent ID required"
        );

        uint256 previousMints = mintedByWallet[msg.sender];

        require(
            previousMints + quantity <= MAX_PER_WALLET,
            "Wallet mint limit exceeded"
        );

        require(
            totalMinted + quantity <= MAX_SUPPLY,
            "Max supply reached"
        );

        // First NFT is free for a wallet that has never minted.
        // Every subsequent NFT costs 0.0005 BNB.
        uint256 freeMints = previousMints == 0 ? 1 : 0;
        uint256 paidQuantity = quantity > freeMints
            ? quantity - freeMints
            : 0;

        uint256 price = paidQuantity * NEXT_MINT_PRICE;

        require(msg.value == price, "Incorrect BNB amount");

        // Update before minting to prevent reentrant mint-limit bypass.
        mintedByWallet[msg.sender] = previousMints + quantity;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = ++totalMinted;

            uint8 selectedImage = uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.prevrandao,
                            block.timestamp,
                            msg.sender,
                            tokenId,
                            blockhash(block.number - 1)
                        )
                    )
                ) % 4
            );

            imageIndex[tokenId] = selectedImage;

            _safeMint(msg.sender, tokenId);

            emit Minted(msg.sender, tokenId, selectedImage);
        }

        if (price > 0) {
            (bool success, ) = payable(owner()).call{value: price}("");
            require(success, "Owner payment failed");
        }

        emit ProceedsForwarded(owner(), price);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        string memory json = string(
            abi.encodePacked(
                '{"name":"ORVYN #',
                tokenId.toString(),
                '","description":"ORVYN pixel robot NFT on BNB Smart Chain.",',
                '"image":"',
                _imageURI(imageIndex[tokenId]),
                '"}'
            )
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            )
        );
    }

    function _imageURI(uint8 index)
        internal
        pure
        returns (string memory)
    {
        if (index == 0) {
            return "ipfs://bafybeig53ybwnnedjzymr5lyiqfvkkbkc5w6bstqqzam2dn6jhosf4qdoq";
        }

        if (index == 1) {
            return "ipfs://bafybeigm6jttxdn3hfbbf24hjioaqr5xblxgvtlcdatzhiaej4ldkec5hu";
        }

        if (index == 2) {
            return "ipfs://bafybeifjovmhp5oezugad7koqo3o7ttpqmzgeswo2obqxa2qs3tsvyyol4";
        }

        return "ipfs://bafybeifpygxksmzoyqg4sznpolzacqmoej63dfc4sl4uznms7psame2g5u";
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "No BNB to withdraw");

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdrawal failed");
    }
}
