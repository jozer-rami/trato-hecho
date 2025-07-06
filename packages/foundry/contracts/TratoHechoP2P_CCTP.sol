// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Deploy on Ethereum Sepolia

import {FunctionsClient} from "@chainlink/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// CCTP Interfaces
interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external returns (uint64 nonce);
}

interface IMessageTransmitter {
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success);
}

/**
 * @title P2P Exchange with Chainlink Functions and CCTP
 * @notice Decentralized peer-to-peer exchange for USDC <-> BOB trades with cross-chain support
 * @dev Uses Chainlink Functions to verify off-chain bank transfers and CCTP for cross-chain USDC transfers
 */
contract TratoHechoP2P_CCTP is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    // ============ CCTP Configuration ============
    
    // CCTP contract addresses (Ethereum Sepolia)
    address constant TOKEN_MESSENGER = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    address constant MESSAGE_TRANSMITTER = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;
    
    // Domain IDs for CCTP (matching the provided config)
    uint32 constant ETH_SEPOLIA_DOMAIN = 0;
    uint32 constant AVAX_FUJI_DOMAIN = 1;
    uint32 constant ARB_SEPOLIA_DOMAIN = 3;
    uint32 constant BASE_SEPOLIA_DOMAIN = 6;
    uint32 constant MATIC_AMOY_DOMAIN = 7;

    // Order status enumeration
    enum OrderStatus {
        Created,        // Available for acceptance
        Accepted,       // Buyer found and committed
        PaymentPending, // Verification in progress
        PaymentVerified,// Chainlink confirmed payment
        Completed,      // USDC transferred successfully
        Cancelled,      // Seller cancelled
        Expired,        // Time expired
        Failed          // Verification failed
    }

    // Core order structure
    struct Order {
        uint256 id;
        address seller;         // Known: order creator
        address buyer;          // Unknown initially, set on acceptance
        uint256 amountUSDC;     // USDC amount to sell (6 decimals)
        uint256 priceBOB;       // BOB amount to receive (2 decimals)
        OrderStatus status;     // Current order state
        uint256 createdAt;      // Creation timestamp
        uint256 deadline;       // Expiration time
        uint32 destinationDomain; // Destination chain domain (0 for same-chain)
        bool isCrossChain;      // Flag to indicate if this is a cross-chain order
    }

    // Cross-chain transfer tracking
    struct CrossChainTransfer {
        uint256 orderId;
        uint32 destinationDomain;
        bytes32 destinationRecipient;
        uint64 cctpNonce;
        bool isPending;
    }

    // Request tracking for Chainlink Functions
    struct RequestIdentity {
        uint256 orderId;
        address requester;
        string referenceId;     // Payment reference ID
    }

    // State variables
    mapping(uint256 => Order) public orders;
    mapping(uint256 => CrossChainTransfer) public crossChainTransfers;
    mapping(bytes32 => RequestIdentity) public requestToOrder;
    uint256 public nextOrderId = 1;
    
    // USDC token contract
    IERC20 public immutable usdcToken;

    // Chainlink Functions configuration
    // Ethereum Sepolia router
    address constant router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant donID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint32 public gasLimit = 300000;

    // Simplified JavaScript source code for banking verification
    // IMPORTANT : I HAD TO PASS THE API KEY AS AN ARGUMENT TO THE FUNCTION CALL INSTEAD OF USING THE SECRETS MANAGER BECAUSE THE SECRETS MANAGER WAS NOT WORKING
    string constant source =
        "const referenceId = args[0];"
        "const apiKey = args[1];"
        "const bankingApiUrl = 'https://bnb-bank-api.ngrok.app';"
        "const apiRequest = Functions.makeHttpRequest({"
            "url: `${bankingApiUrl}/DirectDebit/GetTransactionOutgoing/${referenceId}`,"
            "method: 'GET',"
            "headers: {"
                "Authorization: `Bearer ${apiKey}`,"
            "},"
        "});"
        "const apiResponse = await apiRequest;"
        "console.log('API response data:', JSON.stringify(apiResponse, null, 2));"
        "if (apiResponse.error) {"
            "throw Error('Banking API request failed');"
        "}"
        "const responseData = apiResponse.data;"
        "return Functions.encodeString(responseData.status);";

    // Events
    event OrderCreated(
        uint256 indexed orderId,
        address indexed seller,
        uint256 amountUSDC,
        uint256 priceBOB,
        uint256 deadline
    );
    
    event OrderAccepted(
        uint256 indexed orderId,
        address indexed buyer,
        address indexed seller,
        uint32 destinationDomain,
        bool isCrossChain
    );
    
    event PaymentVerificationRequested(
        uint256 indexed orderId,
        bytes32 indexed requestId,
        address indexed requester
    );
    
    event PaymentVerified(
        uint256 indexed orderId,
        bool verified,
        bytes32 indexed requestId
    );
    
    event OrderCompleted(
        uint256 indexed orderId,
        address indexed seller,
        address indexed buyer,
        uint256 amountUSDC
    );
    
    event CrossChainTransferInitiated(
        uint256 indexed orderId,
        address indexed buyer,
        uint32 destinationDomain,
        address destinationRecipient,
        uint256 amount,
        uint64 nonce
    );
    
    event CrossChainTransferCompleted(
        uint256 indexed orderId,
        bytes32 messageHash
    );
    
    event OrderCancelled(uint256 indexed orderId);
    event OrderExpired(uint256 indexed orderId);

    // Custom errors
    error OrderNotFound(uint256 orderId);
    error OrderAlreadyExpired(uint256 orderId);
    error InvalidOrderStatus(uint256 orderId, OrderStatus expected, OrderStatus actual);
    error UnauthorizedAccess(address caller, address expected);
    error InsufficientUSDCBalance(address seller, uint256 required, uint256 available);
    error InsufficientUSDCAllowance(address seller, uint256 required, uint256 available);
    error InvalidAmount(uint256 amount);
    error InvalidDeadline(uint256 deadline);
    error UnexpectedRequestID(bytes32 requestId);
    error InvalidDestinationDomain(uint32 domain);

    // Modifiers
    modifier validOrder(uint256 orderId) {
        if (orders[orderId].id == 0) revert OrderNotFound(orderId);
        if (orders[orderId].deadline <= block.timestamp) revert OrderAlreadyExpired(orderId);
        _;
    }

    modifier onlyBuyer(uint256 orderId) {
        if (msg.sender != orders[orderId].buyer) {
            revert UnauthorizedAccess(msg.sender, orders[orderId].buyer);
        }
        _;
    }

    modifier onlySeller(uint256 orderId) {
        if (msg.sender != orders[orderId].seller) {
            revert UnauthorizedAccess(msg.sender, orders[orderId].seller);
        }
        _;
    }

    modifier inStatus(uint256 orderId, OrderStatus expectedStatus) {
        OrderStatus actualStatus = orders[orderId].status;
        if (actualStatus != expectedStatus) {
            revert InvalidOrderStatus(orderId, expectedStatus, actualStatus);
        }
        _;
    }

    /**
     * @notice Constructor
     */
    constructor() FunctionsClient(router) ConfirmedOwner(msg.sender) {
        usdcToken = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238); // USDC on Ethereum Sepolia
    }

    /**
     * @notice Set the gas limit for Chainlink Functions requests
     * @param _gasLimit New gas limit value
     */
    function setGasLimit(uint32 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    // ============ Cross-Chain Functions ============
    
    /**
     * @notice Complete order - automatically handles same-chain or cross-chain based on order settings
     * @param orderId The order ID
     */
    function completeOrder(uint256 orderId) 
        external 
        validOrder(orderId) 
        onlySeller(orderId) 
        inStatus(orderId, OrderStatus.PaymentVerified) 
    {
        Order storage order = orders[orderId];
        order.status = OrderStatus.Completed;

        if (order.isCrossChain) {
            // Handle cross-chain transfer
            _completeCrossChainOrder(orderId);
        } else {
            // Handle same-chain transfer
            _completeSameChainOrder(orderId);
        }

        emit OrderCompleted(orderId, order.seller, order.buyer, order.amountUSDC);
    }
    
    /**
     * @notice Internal function to complete same-chain order
     * @param orderId The order ID
     */
    function _completeSameChainOrder(uint256 orderId) internal {
        Order storage order = orders[orderId];
        
        // Transfer USDC from contract (escrow) to buyer
        bool success = usdcToken.transfer(
            order.buyer,
            order.amountUSDC
        );
        
        require(success, "USDC transfer failed");
    }
    
    /**
     * @notice Internal function to complete cross-chain order
     * @param orderId The order ID
     * @dev Uses CCTP v2 for cross-chain USDC transfers
     * @dev Reverts if:
     * - burnToken is not supported
     * - destinationDomain has no TokenMessenger registered
     * - USDC transferFrom/burn fails
     * - maxFee >= amount (we use 0 for no limit)
     * - MessageTransmitterV2#sendMessage reverts
     */
    function _completeCrossChainOrder(uint256 orderId) internal {
        Order storage order = orders[orderId];
        
        // Validate destination domain is supported
        require(_validateDestinationDomain(order.destinationDomain), "Invalid destination domain");
        
        // Store cross-chain details
        crossChainTransfers[orderId] = CrossChainTransfer({
            orderId: orderId,
            destinationDomain: order.destinationDomain,
            destinationRecipient: addressToBytes32(order.buyer),
            cctpNonce: 0,
            isPending: true
        });
        
        // USDC is already in the contract from when the order was created
        // Approve USDC for burning by CCTP TokenMessenger
        usdcToken.approve(TOKEN_MESSENGER, order.amountUSDC);
        
        // Initiate cross-chain transfer using CCTP v2
        ITokenMessenger messenger = ITokenMessenger(TOKEN_MESSENGER);
        
        uint64 nonce = messenger.depositForBurn(
            order.amountUSDC,                    // amount to burn
            order.destinationDomain,             // destination domain
            addressToBytes32(order.buyer),       // mint recipient on destination
            address(usdcToken),                  // burn token (USDC)
            bytes32(0),                          // destinationCaller (0 = any address can broadcast)
            0,                                   // maxFee (0 = no fee limit)
            0                                    // minFinalityThreshold (0 = default)
        );
        
        crossChainTransfers[orderId].cctpNonce = nonce;
        
        emit CrossChainTransferInitiated(
            orderId,
            order.buyer,
            order.destinationDomain,
            order.buyer,
            order.amountUSDC,
            nonce
        );
    }
    
    /**
     * @notice Get cross-chain transfer details
     * @param orderId The order ID
     */
    function getCrossChainTransfer(uint256 orderId) 
        external 
        view 
        returns (CrossChainTransfer memory) 
    {
        return crossChainTransfers[orderId];
    }
    
    /**
     * @notice Check if order was completed cross-chain
     * @param orderId The order ID
     */
    function isCrossChainTransfer(uint256 orderId) 
        external 
        view 
        returns (bool) 
    {
        return crossChainTransfers[orderId].isPending;
    }

    // ============ Helper Functions ============
    
    /**
     * @notice Convert address to bytes32
     */
    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
    
    /**
     * @notice Convert address to bytes32 (public wrapper for testing)
     */
    function addressToBytes32Public(address addr) external pure returns (bytes32) {
        return addressToBytes32(addr);
    }
    
    /**
     * @notice Convert bytes32 to address
     */
    function bytes32ToAddress(bytes32 _buf) internal pure returns (address) {
        return address(uint160(uint256(_buf)));
    }

    /**
     * @notice Get supported destination domains
     */
    function getSupportedDomains() external pure returns (
        uint32[] memory domains,
        string[] memory names
    ) {
        domains = new uint32[](4);
        names = new string[](4);
        
        domains[0] = AVAX_FUJI_DOMAIN;
        names[0] = "Avalanche Fuji";
        
        domains[1] = ARB_SEPOLIA_DOMAIN;
        names[1] = "Arbitrum Sepolia";
        
        domains[2] = BASE_SEPOLIA_DOMAIN;
        names[2] = "Base Sepolia";
        
        domains[3] = MATIC_AMOY_DOMAIN;
        names[3] = "Polygon Amoy";
    }

    /**
     * @notice Validate destination domain
     * @param domain The domain to validate
     */
    function _validateDestinationDomain(uint32 domain) internal pure returns (bool) {
        return domain == AVAX_FUJI_DOMAIN ||
               domain == ARB_SEPOLIA_DOMAIN ||
               domain == BASE_SEPOLIA_DOMAIN ||
               domain == MATIC_AMOY_DOMAIN;
    }

    // ============ Existing Functions (Core P2P functionality) ============

    /**
     * @notice Create a new sell order
     * @param amountUSDC Amount of USDC to sell (6 decimals)
     * @param priceBOB Price in BOB (2 decimals)
     * @param deadline Order expiration timestamp
     * @return orderId The created order ID
     */
    function createSellOrder(
        uint256 amountUSDC,
        uint256 priceBOB,
        uint256 deadline
    ) external returns (uint256 orderId) {
        // Validation
        if (amountUSDC == 0) revert InvalidAmount(amountUSDC);
        if (priceBOB == 0) revert InvalidAmount(priceBOB);
        if (deadline <= block.timestamp) revert InvalidDeadline(deadline);
        
        // Check seller has sufficient USDC balance
        uint256 sellerBalance = usdcToken.balanceOf(msg.sender);
        if (sellerBalance < amountUSDC) {
            revert InsufficientUSDCBalance(msg.sender, amountUSDC, sellerBalance);
        }

        // Check if contract has sufficient allowance from seller
        uint256 allowance = usdcToken.allowance(msg.sender, address(this));
        if (allowance < amountUSDC) {
            revert InsufficientUSDCAllowance(msg.sender, amountUSDC, allowance);
        }

        // Transfer USDC from seller to contract (escrow)
        bool transferSuccess = usdcToken.transferFrom(msg.sender, address(this), amountUSDC);
        require(transferSuccess, "USDC transfer to escrow failed");

        // Create order
        orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            seller: msg.sender,
            buyer: address(0),
            amountUSDC: amountUSDC,
            priceBOB: priceBOB,
            status: OrderStatus.Created,
            createdAt: block.timestamp,
            deadline: deadline,
            destinationDomain: 0, // Will be set by buyer
            isCrossChain: false   // Will be set by buyer
        });



        emit OrderCreated(orderId, msg.sender, amountUSDC, priceBOB, deadline);
    }

    /**
     * @notice Accept an available order with optional destination chain specification
     * @param orderId The order to accept
     * @param destinationDomain Target chain domain (0 for same-chain, or valid CCTP domain)
     */
    function acceptOrder(uint256 orderId, uint32 destinationDomain) 
        external 
        validOrder(orderId) 
        inStatus(orderId, OrderStatus.Created) 
    {
        Order storage order = orders[orderId];
        
        // Seller cannot accept their own order
        if (msg.sender == order.seller) {
            revert UnauthorizedAccess(msg.sender, address(0));
        }

        // Validate destination domain if specified
        if (destinationDomain != ETH_SEPOLIA_DOMAIN) {
            if (!_validateDestinationDomain(destinationDomain)) {
                revert InvalidDestinationDomain(destinationDomain);
            }
        }

        // Set buyer and destination information
        order.buyer = msg.sender;
        order.destinationDomain = destinationDomain;
        order.isCrossChain = (destinationDomain != ETH_SEPOLIA_DOMAIN);
        order.status = OrderStatus.Accepted;

        emit OrderAccepted(orderId, msg.sender, order.seller, destinationDomain, order.isCrossChain);
    }

    /**
     * @notice Accept an available order (same-chain only, for backward compatibility)
     * @param orderId The order to accept
     */
    function acceptOrderSameChain(uint256 orderId) 
        external 
        validOrder(orderId) 
        inStatus(orderId, OrderStatus.Created) 
    {
        Order storage order = orders[orderId];
        
        // Seller cannot accept their own order
        if (msg.sender == order.seller) {
            revert UnauthorizedAccess(msg.sender, address(0));
        }

        // Set buyer and destination information for same-chain
        order.buyer = msg.sender;
        order.destinationDomain = ETH_SEPOLIA_DOMAIN;
        order.isCrossChain = false;
        order.status = OrderStatus.Accepted;

        emit OrderAccepted(orderId, msg.sender, order.seller, ETH_SEPOLIA_DOMAIN, false);
    }

    /**
     * @notice Verify payment using Chainlink Functions
     * @param orderId The order ID
     * @param subscriptionId Chainlink subscription ID
     * @param referenceId Payment reference ID (e.g., "P2P-ORDER-42")
     * @param apiKey Banking API key // THIS SHOULD BE A SECRET !! NOT MANAGED YET
     * @return requestId Chainlink request ID
     */
    function verifyPayment(
        uint256 orderId,
        uint64 subscriptionId,
        string calldata referenceId,
        string calldata apiKey
    ) external 
      validOrder(orderId) 
      onlyBuyer(orderId) 
      inStatus(orderId, OrderStatus.Accepted) 
      returns (bytes32 requestId) {
        
        // Update order status
        orders[orderId].status = OrderStatus.PaymentPending;

        // Prepare Chainlink Functions request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        
        string[] memory args = new string[](2);
        args[0] = referenceId;  // Payment reference ID
        args[1] = apiKey;       // Banking API key
        
        req.setArgs(args);

        // Send request
        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        // Store request mapping
        requestToOrder[requestId] = RequestIdentity({
            orderId: orderId,
            requester: msg.sender,
            referenceId: referenceId
        });

        emit PaymentVerificationRequested(orderId, requestId, msg.sender);
    }

    /**
     * @notice Chainlink Functions callback
     * @param requestId The request ID
     * @param response The response data (status string)
     * @param err Any error data
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        RequestIdentity memory identity = requestToOrder[requestId];
        
        if (identity.orderId == 0) {
            revert UnexpectedRequestID(requestId);
        }

        Order storage order = orders[identity.orderId];

        // Handle errors
        if (err.length > 0) {
            order.status = OrderStatus.Failed;
            emit PaymentVerified(identity.orderId, false, requestId);
            return;
        }

        // Decode response (status string)
        string memory status = string(response);
        
        // Check if payment status indicates success
        // Assuming the banking API returns statuses like "completed", "success", "confirmed"
        bool verified = _isPaymentStatusValid(status);

        // Update order status
        if (verified) {
            order.status = OrderStatus.PaymentVerified;
        } else {
            order.status = OrderStatus.Failed;
        }

        emit PaymentVerified(identity.orderId, verified, requestId);
    }

    /**
     * @notice Check if payment status indicates successful payment
     * @param status The status string from banking API
     * @return verified True if payment is confirmed
     */
    function _isPaymentStatusValid(string memory status) internal pure returns (bool verified) {
        // Check for common success statuses
        if (_compareStrings(status, "completed") || 
            _compareStrings(status, "success") || 
            _compareStrings(status, "confirmed") ||
            _compareStrings(status, "processed")) {
            return true;
        }
        
        return false;
    }

    /**
     * @notice Compare two strings (case-insensitive)
     * @param a First string
     * @param b Second string
     * @return True if strings are equal
     */
    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_toLower(a))) == keccak256(abi.encodePacked(b));
    }

    /**
     * @notice Convert string to lowercase
     * @param str Input string
     * @return Lowercase string
     */
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    /**
     * @notice Cancel an order (only seller, only if not accepted)
     * @param orderId The order ID
     */
    function cancelOrder(uint256 orderId) 
        external 
        onlySeller(orderId) 
        inStatus(orderId, OrderStatus.Created) 
    {
        orders[orderId].status = OrderStatus.Cancelled;
        emit OrderCancelled(orderId);
    }

    /**
     * @notice Mark expired orders (can be called by anyone)
     * @param orderId The order ID
     */
    function markExpired(uint256 orderId) external {
        Order storage order = orders[orderId];
        
        if (order.id == 0) revert OrderNotFound(orderId);
        if (order.deadline > block.timestamp) revert OrderAlreadyExpired(orderId);
        if (order.status == OrderStatus.Completed || 
            order.status == OrderStatus.Cancelled) {
            return; // Already finalized
        }

        order.status = OrderStatus.Expired;
        emit OrderExpired(orderId);
    }

    // View functions for marketplace

    /**
     * @notice Get available orders for browsing
     * @param limit Maximum number of orders to return
     * @return orderIds Array of available order IDs
     */
    function getAvailableOrders(uint256 limit) external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](limit);

        for (uint256 i = 1; i < nextOrderId && count < limit; i++) {
            Order storage order = orders[i];
            if (order.status == OrderStatus.Created && 
                order.deadline > block.timestamp) {
                tempIds[count] = i;
                count++;
            }
        }

        // Create properly sized array
        orderIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = tempIds[i];
        }
    }

    /**
     * @notice Get orders by seller
     * @param seller The seller address
     * @param limit Maximum number of orders to return
     * @return orderIds Array of order IDs
     */
    function getOrdersBySeller(address seller, uint256 limit) 
        external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](limit);

        for (uint256 i = 1; i < nextOrderId && count < limit; i++) {
            if (orders[i].seller == seller) {
                tempIds[count] = i;
                count++;
            }
        }

        orderIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = tempIds[i];
        }
    }

    /**
     * @notice Get orders by buyer
     * @param buyer The buyer address
     * @param limit Maximum number of orders to return
     * @return orderIds Array of order IDs
     */
    function getOrdersByBuyer(address buyer, uint256 limit) 
        external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](limit);

        for (uint256 i = 1; i < nextOrderId && count < limit; i++) {
            if (orders[i].buyer == buyer) {
                tempIds[count] = i;
                count++;
            }
        }

        orderIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = tempIds[i];
        }
    }

    /**
     * @notice Get order details
     * @param orderId The order ID
     * @return order The order struct
     */
    function getOrder(uint256 orderId) external view returns (Order memory order) {
        order = orders[orderId];
    }

    /**
     * @notice Get request identity
     * @param requestId The Chainlink request ID
     * @return identity The request identity
     */
    function getRequestIdentity(bytes32 requestId) 
        external view returns (RequestIdentity memory identity) {
        identity = requestToOrder[requestId];
    }

    // Utility functions

    /**
     * @notice Convert uint256 to string
     * @param value The value to convert
     * @return String representation
     */
    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // TEST-ONLY: Set order status for local testing
    function setOrderStatus(uint256 orderId, OrderStatus status) public {
        orders[orderId].status = status;
    }
}