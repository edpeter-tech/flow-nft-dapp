// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Collection.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title CollectionFactory
 * @notice Factory contract for deploying NFT collection instances using minimal proxy pattern (EIP-1167)
 * @dev Uses OpenZeppelin Clones library for gas-efficient collection deployment
 */
contract CollectionFactory {
    // ===============================
    //        STATE VARIABLES
    // ===============================
    // Implementation contract address for cloning
    address public immutable collectionImplementation;
    
    // Mapping of creator address to their collection addresses
    mapping(address => address[]) private _creatorCollections;
    
    // Array of all created collections
    address[] private _allCollections;

    // ===============================
    //             ERRORS
    // ===============================
    error InvalidRoyaltyPercentage();
    error InvalidMaxSupply();

    // ===============================
    //             EVENTS
    // ===============================
    event CollectionCreated(
        address indexed collectionAddress,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply
    );

    // ===============================
    //          CONSTRUCTOR
    // ===============================
    /**
     * @notice Initialize the factory with a collection implementation
     * @dev Deploys a single implementation contract that will be cloned
     */
    constructor() {
        // Deploy the implementation contract
        // This will be cloned for each new collection
        collectionImplementation = address(
            new Collection(
                "Implementation",
                "IMPL",
                "",
                1,
                0,
                address(this)
            )
        );
    }

    // ===============================
    //      COLLECTION CREATION
    // ===============================
    /**
     * @notice Create a new NFT collection using minimal proxy pattern
     * @param name_ Collection name
     * @param symbol_ Collection symbol
     * @param baseURI_ Base URI for token metadata
     * @param maxSupply_ Maximum number of tokens that can be minted
     * @param royaltyBps_ Royalty percentage in basis points (0-1000 = 0-10%)
     * @return collectionAddress Address of the newly created collection
     */
    function createCollection(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint96 royaltyBps_
    ) external returns (address collectionAddress) {
        // Validate inputs
        if (royaltyBps_ > 1000) {
            revert InvalidRoyaltyPercentage();
        }
        if (maxSupply_ == 0) {
            revert InvalidMaxSupply();
        }

        // Deploy new collection contract using minimal proxy
        Collection newCollection = new Collection(
            name_,
            symbol_,
            baseURI_,
            maxSupply_,
            royaltyBps_,
            msg.sender
        );

        collectionAddress = address(newCollection);

        // Store collection address
        _creatorCollections[msg.sender].push(collectionAddress);
        _allCollections.push(collectionAddress);

        emit CollectionCreated(
            collectionAddress,
            msg.sender,
            name_,
            symbol_,
            maxSupply_
        );

        return collectionAddress;
    }

    // ===============================
    //         VIEW FUNCTIONS
    // ===============================
    /**
     * @notice Get all collections created by a specific creator
     * @param creator Address of the creator
     * @return Array of collection addresses
     */
    function getCollectionsByCreator(address creator) external view returns (address[] memory) {
        return _creatorCollections[creator];
    }

    /**
     * @notice Get all collections created through this factory
     * @return Array of all collection addresses
     */
    function getAllCollections() external view returns (address[] memory) {
        return _allCollections;
    }

    /**
     * @notice Get the total number of collections created
     * @return Total number of collections
     */
    function getTotalCollections() external view returns (uint256) {
        return _allCollections.length;
    }

    /**
     * @notice Get the number of collections created by a specific creator
     * @param creator Address of the creator
     * @return Number of collections
     */
    function getCreatorCollectionCount(address creator) external view returns (uint256) {
        return _creatorCollections[creator].length;
    }
}
