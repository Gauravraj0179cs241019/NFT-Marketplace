// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 private _tokenIdCounter;
    uint256 private _listingIdCounter;
    
    // Marketplace fee percentage (2.5%)
    uint256 public marketplaceFee = 250; // 250 basis points = 2.5%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    struct Listing {
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
    }
    
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => uint256) public tokenToListingId;
    
    event NFTMinted(uint256 indexed tokenId, address indexed to, string tokenURI);
    event NFTListed(uint256 indexed listingId, uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed listingId, uint256 indexed tokenId, address indexed buyer, address seller, uint256 price);
    event ListingCancelled(uint256 indexed listingId, uint256 indexed tokenId);
    
    constructor() ERC721("NFT Marketplace", "NFTM") Ownable(msg.sender) {}
    
    /**
     * @dev Core Function 1: Mint NFT
     * Allows users to mint new NFTs with metadata URI
     * @param to Address to mint the NFT to
     * @param tokenURI Metadata URI for the NFT
     * @return tokenId The ID of the newly minted token
     */
    function mintNFT(address to, string memory tokenURI) public returns (uint256) {
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        emit NFTMinted(tokenId, to, tokenURI);
        return tokenId;
    }
    
    /**
     * @dev Core Function 2: List NFT for Sale
     * Allows NFT owners to list their tokens for sale
     * @param tokenId The ID of the token to list
     * @param price The price in wei to list the token for
     * @return listingId The ID of the created listing
     */
    function listNFT(uint256 tokenId, uint256 price) public returns (uint256) {
        require(tokenId < _tokenIdCounter, "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Only owner can list NFT");
        require(price > 0, "Price must be greater than 0");
        require(getApproved(tokenId) == address(this) || isApprovedForAll(msg.sender, address(this)), 
                "Contract not approved to transfer NFT");
        
        uint256 listingId = _listingIdCounter;
        _listingIdCounter++;
        
        listings[listingId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            active: true
        });
        
        tokenToListingId[tokenId] = listingId;
        
        emit NFTListed(listingId, tokenId, msg.sender, price);
        return listingId;
    }
    
    /**
     * @dev Core Function 3: Buy NFT
     * Allows users to purchase listed NFTs
     * @param listingId The ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) public payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(msg.value == listing.price, "Incorrect payment amount");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        require(listing.tokenId < _tokenIdCounter, "Token does not exist");
        
        address seller = listing.seller;
        uint256 tokenId = listing.tokenId;
        uint256 price = listing.price;
        
        // Mark listing as inactive
        listing.active = false;
        delete tokenToListingId[tokenId];
        
        // Calculate fees
        uint256 fee = (price * marketplaceFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = price - fee;
        
        // Transfer NFT to buyer
        _transfer(seller, msg.sender, tokenId);
        
        // Transfer payments
        payable(seller).transfer(sellerAmount);
        payable(owner()).transfer(fee);
        
        emit NFTSold(listingId, tokenId, msg.sender, seller, price);
    }
    
    /**
     * @dev Cancel NFT listing
     * Allows sellers to cancel their active listings
     * @param listingId The ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) public {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(listing.seller == msg.sender, "Only seller can cancel listing");
        
        listing.active = false;
        delete tokenToListingId[listing.tokenId];
        
        emit ListingCancelled(listingId, listing.tokenId);
    }
    
    /**
     * @dev Get active listing by token ID
     * @param tokenId The token ID to check
     * @return Listing details if active, otherwise reverts
     */
    function getListingByTokenId(uint256 tokenId) public view returns (Listing memory) {
        uint256 listingId = tokenToListingId[tokenId];
        require(listings[listingId].active, "No active listing for this token");
        return listings[listingId];
    }
    
    /**
     * @dev Update marketplace fee (only owner)
     * @param newFee New fee in basis points (max 1000 = 10%)
     */
    function setMarketplaceFee(uint256 newFee) public onlyOwner {
        require(newFee <= 1000, "Fee cannot exceed 10%");
        marketplaceFee = newFee;
    }
    
    /**
     * @dev Get total number of tokens minted
     * @return Total token count
     */
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    /**
     * @dev Get total number of listings created
     * @return Total listing count
     */
    function totalListings() public view returns (uint256) {
        return _listingIdCounter;
    }
    
    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        payable(owner()).transfer(balance);
    }
}
