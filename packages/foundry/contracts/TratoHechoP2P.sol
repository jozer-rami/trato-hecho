// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Deploy on Ethereum Sepolia

import {FunctionsClient} from "@chainlink/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title P2P Exchange with Chainlink Functions
 * @notice Decentralized peer-to-peer exchange for USDC <-> BOB trades
 * @dev Uses Chainlink Functions to verify off-chain bank transfers
 */
contract TratoHechoP2P is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

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
    }

    // Request tracking for Chainlink Functions
    struct RequestIdentity {
        uint256 orderId;
        address requester;
        string referenceId;     // Payment reference ID
    }

    // State variables
    mapping(uint256 => Order) public orders;
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
        address indexed seller
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
    
    event OrderCancelled(uint256 indexed orderId);
    event OrderExpired(uint256 indexed orderId);

    // Custom errors
    error OrderNotFound(uint256 orderId);
    error OrderAlreadyExpired(uint256 orderId);
    error InvalidOrderStatus(uint256 orderId, OrderStatus expected, OrderStatus actual);
    error UnauthorizedAccess(address caller, address expected);
    error InsufficientUSDCBalance(address seller, uint256 required, uint256 available);
    error InvalidAmount(uint256 amount);
    error InvalidDeadline(uint256 deadline);
    error UnexpectedRequestID(bytes32 requestId);

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
            deadline: deadline
        });

        emit OrderCreated(orderId, msg.sender, amountUSDC, priceBOB, deadline);
    }

    /**
     * @notice Accept an available order
     * @param orderId The order to accept
     */
    function acceptOrder(uint256 orderId) 
        external 
        validOrder(orderId) 
        inStatus(orderId, OrderStatus.Created) 
    {
        Order storage order = orders[orderId];
        
        // Seller cannot accept their own order
        if (msg.sender == order.seller) {
            revert UnauthorizedAccess(msg.sender, address(0));
        }

        // Set buyer and update status
        order.buyer = msg.sender;
        order.status = OrderStatus.Accepted;

        emit OrderAccepted(orderId, msg.sender, order.seller);
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
     * @notice Complete the order by transferring USDC
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

        // Transfer USDC from seller to buyer
        bool success = usdcToken.transferFrom(
            order.seller,
            order.buyer,
            order.amountUSDC
        );
        
        require(success, "USDC transfer failed");

        emit OrderCompleted(orderId, order.seller, order.buyer, order.amountUSDC);
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
}