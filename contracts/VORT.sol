
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VORT is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant MAX_PER_WALLET = 10;

    uint256 public constant FREE_MINT_LIMIT = 2;
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
        ERC721("VORT", "VORT")
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

        // First two lifetime mints are free.
        uint256 freeRemaining = previousMints < FREE_MINT_LIMIT
            ? FREE_MINT_LIMIT - previousMints
            : 0;

        uint256 paidQuantity = quantity > freeRemaining
            ? quantity - freeRemaining
            : 0;

        uint256 price = paidQuantity * NEXT_MINT_PRICE;

        require(msg.value == price, "Incorrect BNB amount");

        // Update mint count before external NFT receiver callbacks.
        mintedByWallet[msg.sender] = previousMints + quantity;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = ++totalMinted;

            // Select one of three artwork variants.
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
                ) % 3
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
                '{"name":"VORT #',
                tokenId.toString(),
                '","description":"VORT is a monochrome digital art collection exploring glitch patterns, fragmented pixels, and abstract forms on BNB Smart Chain.",',
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
            return "ipfs://bafybeiblvmr6ovyabgysbsmbw6h4aywdfo5gpldmpvn7g6zexce5yoseue";
        }

        if (index == 1) {
            return "ipfs://bafkreievgkiuhvieljstohnfeudhhfmvhekumxnhmt4o3hgctith5kp3fi";
        }

        return "ipfs://bafkreibhiurbhfu7o7njaig2jkug2h6rtqrkicxgcnxzuvuvzv6wowyema";
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "No BNB to withdraw");

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdrawal failed");
    }
}
