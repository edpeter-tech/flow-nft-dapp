// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Collection
 * @notice ERC-721 collection contract with batch minting capability
 * @dev Implements ERC-721 and ERC-2981 for royalty support
 */
contract Collection is ERC721, Ownable, ERC2981 {
    using Strings for uint256;

    // ===============================
    //        STATE VARIABLES
    // ===============================
    string private _baseTokenURI;
    uint256 public immutable maxSupply;
    uint256 public totalSupply;

    // ===============================
    //             ERRORS
    // ===============================
    error MaxSupplyExceeded();
    error InvalidQuantity();
    error InvalidRoyaltyPercentage();

    // ===============================
    //             EVENTS
    // ===============================
    event BatchMinted(
        address indexed to,
        uint256 quantity,
        uint256 startTokenId
    );
    event BaseURIUpdated(string newBaseURI);

    // ===============================
    //          CONSTRUCTOR
    // ===============================
    /**
     * @notice Initialize a new NFT collection
     * @param name_ Collection name
     * @param symbol_ Collection symbol
     * @param baseURI_ Base URI for token metadata
     * @param maxSupply_ Maximum number of tokens that can be minted
     * @param royaltyBps_ Royalty percentage in basis points (0-1000 = 0-10%)
     * @param creator_ Address of the collection creator (receives royalties)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint96 royaltyBps_,
        address creator_
    ) ERC721(name_, symbol_) Ownable(creator_) {
        if (royaltyBps_ > 1000) {
            revert InvalidRoyaltyPercentage();
        }

        _baseTokenURI = baseURI_;
        maxSupply = maxSupply_;
        totalSupply = 0;

        // Set royalty for the collection
        _setDefaultRoyalty(creator_, royaltyBps_);
    }

    // ===============================
    //         MINTING LOGIC
    // ===============================
    /**
     * @notice Batch mint multiple tokens to a specified address
     * @param to Address to receive the minted tokens
     * @param quantity Number of tokens to mint
     * @dev Only callable by collection owner (creator)
     */
    function batchMint(address to, uint256 quantity) external onlyOwner {
        if (quantity == 0) {
            revert InvalidQuantity();
        }
        if (totalSupply + quantity > maxSupply) {
            revert MaxSupplyExceeded();
        }

        uint256 startTokenId = totalSupply + 1;

        for (uint256 i = 0; i < quantity; i++) {
            totalSupply++;
            uint256 tokenId = totalSupply;
            _safeMint(to, tokenId);
        }

        emit BatchMinted(to, quantity, startTokenId);
    }

    // ===============================
    //       METADATA FUNCTIONS
    // ===============================
    /**
     * @notice Get the base URI for token metadata
     * @return Base URI string
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Get the full token URI for a specific token
     * @param tokenId Token ID to query
     * @return Full token URI (baseURI + tokenId + .json)
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
                : "";
    }

    /**
     * @notice Update the base URI for token metadata
     * @param newBaseURI New base URI string
     * @dev Only callable by collection owner
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ===============================
    //      ROYALTY FUNCTIONS
    // ===============================
    /**
     * @notice Update the default royalty information
     * @param receiver Address to receive royalty payments
     * @param feeNumerator Royalty fee in basis points
     * @dev Only callable by collection owner
     */
    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        if (feeNumerator > 1000) {
            revert InvalidRoyaltyPercentage();
        }
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    // ===============================
    //     INTERFACE SUPPORT
    // ===============================
    /**
     * @notice Check if contract supports a specific interface
     * @param interfaceId Interface identifier to check
     * @return bool True if interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
