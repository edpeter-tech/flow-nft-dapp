// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/**
 * @title FlowNFT
 * @notice NFT contract that supports individual metadata URIs for each token
 * @dev Uses ERC721URIStorage to store unique metadata URI per token
 */
contract FlowNFT is ERC721URIStorage, Ownable, ReentrancyGuard, ERC2981 {
    uint256 public immutable maxSupply;
    uint256 public mintPrice = 1000 ether;
    uint256 public maxPerWallet;
    bool public saleActive = false;
    uint256 public totalMinted = 0;
    uint256 public ownerReserve;

    // ===============================
    //             EVENTS
    // ===============================
    event Minted(
        address indexed minter,
        uint256 indexed tokenId,
        string tokenURI
    );
    event BatchMint(address indexed minter, uint256 quantity);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _maxPerWallet,
        uint256 _ownerReserve,
        address royaltyReceiver,
        uint96 royaltyFee
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        maxSupply = _maxSupply;
        maxPerWallet = _maxPerWallet;
        ownerReserve = _ownerReserve;
        _setDefaultRoyalty(royaltyReceiver, royaltyFee);
    }

    // ============================================================
    //                PUBLIC MINT WITH TOKEN URI
    // ============================================================

    /**
     * @notice Mint a single NFT with custom metadata URI
     * @param tokenURI_ IPFS URI for the token metadata
     */
    function mint(string calldata tokenURI_) external payable nonReentrant {
        require(saleActive, "Sale is OFF");
        require(bytes(tokenURI_).length > 0, "Empty token URI");
        require(totalMinted + 1 + ownerReserve <= maxSupply, "Exceeds supply");
        require(msg.value == mintPrice, "Wrong ETH amount");
        require(
            balanceOf(msg.sender) + 1 <= maxPerWallet,
            "Wallet limit exceeded"
        );

        totalMinted++;
        uint256 tokenId = totalMinted;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI_);

        emit Minted(msg.sender, tokenId, tokenURI_);
    }

    /**
     * @notice Mint multiple NFTs (batch mint without individual URIs)
     * @dev Token URIs must be set separately after minting
     */
    function mintBatch(uint256 quantity) external payable nonReentrant {
        require(saleActive, "Sale is OFF");
        require(quantity > 0, "Invalid quantity");
        require(
            totalMinted + quantity + ownerReserve <= maxSupply,
            "Exceeds supply"
        );
        require(msg.value == mintPrice * quantity, "Wrong ETH amount");
        require(
            balanceOf(msg.sender) + quantity <= maxPerWallet,
            "Wallet limit exceeded"
        );

        for (uint256 i = 0; i < quantity; i++) {
            totalMinted++;
            _safeMint(msg.sender, totalMinted);
        }

        emit BatchMint(msg.sender, quantity);
    }

    // ============================================================
    //                OWNER MINT (RESERVED SUPPLY)
    // ============================================================

    /**
     * @notice Owner mint with custom token URI
     */
    function ownerMint(
        address to,
        string calldata tokenURI_
    ) external onlyOwner {
        require(bytes(tokenURI_).length > 0, "Empty token URI");
        require(totalMinted + 1 <= maxSupply, "Exceeds max supply");
        require(ownerReserve >= 1, "Not enough reserve");

        ownerReserve--;
        totalMinted++;
        uint256 tokenId = totalMinted;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);

        emit Minted(to, tokenId, tokenURI_);
    }

    /**
     * @notice Batch owner mint without URIs (URIs set separately)
     */
    function ownerMintBatch(address to, uint256 quantity) external onlyOwner {
        require(quantity > 0, "Invalid quantity");
        require(totalMinted + quantity <= maxSupply, "Exceeds max supply");
        require(ownerReserve >= quantity, "Not enough reserve");

        ownerReserve -= quantity;

        for (uint256 i = 0; i < quantity; i++) {
            totalMinted++;
            _safeMint(to, totalMinted);
        }

        emit BatchMint(to, quantity);
    }

    /**
     * @notice Set token URI for an existing token (owner only)
     * @dev Useful for setting URIs after batch minting
     */
    function setTokenURI(
        uint256 tokenId,
        string calldata tokenURI_
    ) external onlyOwner {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        _setTokenURI(tokenId, tokenURI_);
    }

    /**
     * @notice Batch set token URIs
     */
    function setTokenURIBatch(
        uint256[] calldata tokenIds,
        string[] calldata tokenURIs
    ) external onlyOwner {
        require(tokenIds.length == tokenURIs.length, "Array mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(_ownerOf(tokenIds[i]) != address(0), "Nonexistent token");
            _setTokenURI(tokenIds[i], tokenURIs[i]);
        }
    }

    // ============================================================
    //                        ADMIN
    // ============================================================

    function toggleSale() external onlyOwner {
        saleActive = !saleActive;
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    function setMaxPerWallet(uint256 newLimit) external onlyOwner {
        maxPerWallet = newLimit;
    }

    function setOwnerReserve(uint256 newReserve) external onlyOwner {
        ownerReserve = newReserve;
    }

    function setDefaultRoyalty(
        address receiver,
        uint96 fee
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, fee);
    }

    function withdraw(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        (bool success, ) = to.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // ============================================================
    //                    INTERFACE SUPPORT
    // ============================================================

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
