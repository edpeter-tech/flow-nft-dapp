// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Marketplace
 * @notice NFT marketplace contract for listing, buying, and selling NFTs with royalty support
 * @dev Implements escrow mechanism and automatic royalty distribution
 */
contract Marketplace is ReentrancyGuard, Ownable {
    // ===============================
    //        STATE VARIABLES
    // ===============================
    
    // Marketplace fee in basis points (250 = 2.5%)
    uint96 public constant MARKETPLACE_FEE_BPS = 250;
    uint96 public constant BPS_DENOMINATOR = 10000;

    // Listing structure
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
        uint256 listedAt;
    }

    // Mapping: nftContract => tokenId => Listing
    mapping(address => mapping(uint256 => Listing)) private _listings;

    // Tracking listings by collection
    mapping(address => uint256[]) private _collectionListings;

    // Tracking listings by seller
    mapping(address => uint256[]) private _sellerListingIds;
    mapping(uint256 => Listing) private _listingById;
    uint256 private _nextListingId;

    // ===============================
    //             ERRORS
    // ===============================
    error NotTokenOwner();
    error NotApproved();
    error InvalidPrice();
    error ListingNotActive();
    error InsufficientPayment();
    error UnauthorizedAccess();
    error TransferFailed();

    // ===============================
    //             EVENTS
    // ===============================
    event NFTListed(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        uint256 listedAt
    );

    event ListingCancelled(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed seller
    );

    event NFTPurchased(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed buyer,
        address seller,
        uint256 price,
        uint256 royaltyAmount,
        uint256 marketplaceFee
    );

    // ===============================
    //          CONSTRUCTOR
    // ===============================
    constructor() Ownable(msg.sender) {
        _nextListingId = 1;
    }

    // ===============================
    //       LISTING FUNCTIONS
    // ===============================
    
    /**
     * @notice List an NFT for sale
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param price Listing price in wei
     * @dev Transfers NFT to marketplace escrow
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external nonReentrant {
        // Validate price
        if (price == 0) {
            revert InvalidPrice();
        }

        IERC721 nft = IERC721(nftContract);

        // Verify ownership
        if (nft.ownerOf(tokenId) != msg.sender) {
            revert NotTokenOwner();
        }

        // Check approval
        if (
            nft.getApproved(tokenId) != address(this) &&
            !nft.isApprovedForAll(msg.sender, address(this))
        ) {
            revert NotApproved();
        }

        // Transfer NFT to marketplace escrow
        nft.transferFrom(msg.sender, address(this), tokenId);

        // Create listing
        _listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true,
            listedAt: block.timestamp
        });

        // Track listing
        _collectionListings[nftContract].push(tokenId);
        
        uint256 listingId = _nextListingId++;
        _listingById[listingId] = _listings[nftContract][tokenId];
        _sellerListingIds[msg.sender].push(listingId);

        emit NFTListed(nftContract, tokenId, msg.sender, price, block.timestamp);
    }

    /**
     * @notice Cancel a listing and return NFT to seller
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to cancel listing for
     */
    function cancelListing(
        address nftContract,
        uint256 tokenId
    ) external nonReentrant {
        Listing storage listing = _listings[nftContract][tokenId];

        // Verify listing is active
        if (!listing.active) {
            revert ListingNotActive();
        }

        // Verify caller is the seller
        if (listing.seller != msg.sender) {
            revert UnauthorizedAccess();
        }

        // Mark listing as inactive
        listing.active = false;

        // Return NFT to seller
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);

        emit ListingCancelled(nftContract, tokenId, msg.sender);
    }

    // ===============================
    //      PURCHASE FUNCTIONS
    // ===============================
    
    /**
     * @notice Purchase a listed NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to purchase
     * @dev Handles payment distribution: royalty, marketplace fee, seller payment
     */
    function buyNFT(
        address nftContract,
        uint256 tokenId
    ) external payable nonReentrant {
        Listing storage listing = _listings[nftContract][tokenId];

        // Verify listing is active
        if (!listing.active) {
            revert ListingNotActive();
        }

        // Verify sufficient payment
        if (msg.value < listing.price) {
            revert InsufficientPayment();
        }

        uint256 salePrice = listing.price;
        address seller = listing.seller;

        // Mark listing as inactive
        listing.active = false;

        // Calculate royalty using ERC-2981
        uint256 royaltyAmount = 0;
        address royaltyReceiver = address(0);
        
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (
            address receiver,
            uint256 amount
        ) {
            royaltyAmount = amount;
            royaltyReceiver = receiver;
        } catch {
            // No royalty if contract doesn't support ERC-2981
            royaltyAmount = 0;
        }

        // Calculate marketplace fee (2.5%)
        uint256 marketplaceFee = (salePrice * MARKETPLACE_FEE_BPS) / BPS_DENOMINATOR;

        // Calculate seller payment
        uint256 sellerPayment = salePrice - royaltyAmount - marketplaceFee;

        // Transfer NFT to buyer
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);

        // Distribute payments
        if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
            (bool royaltySuccess, ) = payable(royaltyReceiver).call{value: royaltyAmount}("");
            if (!royaltySuccess) {
                revert TransferFailed();
            }
        }

        if (marketplaceFee > 0) {
            (bool feeSuccess, ) = payable(owner()).call{value: marketplaceFee}("");
            if (!feeSuccess) {
                revert TransferFailed();
            }
        }

        (bool sellerSuccess, ) = payable(seller).call{value: sellerPayment}("");
        if (!sellerSuccess) {
            revert TransferFailed();
        }

        // Refund excess payment
        if (msg.value > salePrice) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - salePrice}("");
            if (!refundSuccess) {
                revert TransferFailed();
            }
        }

        emit NFTPurchased(
            nftContract,
            tokenId,
            msg.sender,
            seller,
            salePrice,
            royaltyAmount,
            marketplaceFee
        );
    }

    // ===============================
    //       QUERY FUNCTIONS
    // ===============================
    
    /**
     * @notice Get listing details for a specific NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to query
     * @return Listing struct
     */
    function getListing(
        address nftContract,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return _listings[nftContract][tokenId];
    }

    /**
     * @notice Get all listings for a specific collection
     * @param nftContract Address of the NFT contract
     * @return Array of Listing structs
     */
    function getListingsByCollection(
        address nftContract
    ) external view returns (Listing[] memory) {
        uint256[] memory tokenIds = _collectionListings[nftContract];
        uint256 activeCount = 0;

        // Count active listings
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (_listings[nftContract][tokenIds[i]].active) {
                activeCount++;
            }
        }

        // Create array of active listings
        Listing[] memory activeListings = new Listing[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            Listing memory listing = _listings[nftContract][tokenIds[i]];
            if (listing.active) {
                activeListings[index] = listing;
                index++;
            }
        }

        return activeListings;
    }

    /**
     * @notice Get all listings by a specific seller
     * @param seller Address of the seller
     * @return Array of Listing structs
     */
    function getListingsBySeller(
        address seller
    ) external view returns (Listing[] memory) {
        uint256[] memory listingIds = _sellerListingIds[seller];
        uint256 activeCount = 0;

        // Count active listings
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (_listingById[listingIds[i]].active) {
                activeCount++;
            }
        }

        // Create array of active listings
        Listing[] memory activeListings = new Listing[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < listingIds.length; i++) {
            Listing memory listing = _listingById[listingIds[i]];
            if (listing.active) {
                activeListings[index] = listing;
                index++;
            }
        }

        return activeListings;
    }

    /**
     * @notice Get all active listings with pagination support
     * @param offset Starting index for pagination
     * @param limit Maximum number of listings to return
     * @return Array of Listing structs
     */
    function getAllActiveListings(
        uint256 offset,
        uint256 limit
    ) external view returns (Listing[] memory) {
        // Collect all active listings
        uint256 totalActive = 0;
        
        // First pass: count active listings
        for (uint256 i = 1; i < _nextListingId; i++) {
            if (_listingById[i].active) {
                totalActive++;
            }
        }

        // Calculate actual return size
        uint256 startIndex = offset;
        uint256 endIndex = offset + limit;
        
        if (startIndex >= totalActive) {
            return new Listing[](0);
        }
        
        if (endIndex > totalActive) {
            endIndex = totalActive;
        }
        
        uint256 returnSize = endIndex - startIndex;
        Listing[] memory paginatedListings = new Listing[](returnSize);

        // Second pass: collect active listings with pagination
        uint256 currentIndex = 0;
        uint256 resultIndex = 0;

        for (uint256 i = 1; i < _nextListingId && resultIndex < returnSize; i++) {
            if (_listingById[i].active) {
                if (currentIndex >= startIndex && currentIndex < endIndex) {
                    paginatedListings[resultIndex] = _listingById[i];
                    resultIndex++;
                }
                currentIndex++;
            }
        }

        return paginatedListings;
    }

    /**
     * @notice Get total number of active listings
     * @return Total count of active listings
     */
    function getTotalActiveListings() external view returns (uint256) {
        uint256 totalActive = 0;
        
        for (uint256 i = 1; i < _nextListingId; i++) {
            if (_listingById[i].active) {
                totalActive++;
            }
        }

        return totalActive;
    }
}
