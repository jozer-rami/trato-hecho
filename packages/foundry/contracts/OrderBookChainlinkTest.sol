// packages/foundry/contracts/OrderBookChainlinkTest.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/v0.8/functions/FunctionsClient.sol";
import "@chainlink/contracts/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OrderBookChainlinkTest
 * @notice Simplified OrderBook contract for testing Chainlink Functions integration
 * @dev Focuses on payment verification functionality with mocked orders
 */
contract OrderBookChainlinkTest is FunctionsClient, Ownable {
    using FunctionsRequest for FunctionsRequest.Request;

    // Chainlink Functions configuration
    uint64 public subscriptionId;
    uint32 public gasLimit;
    bytes32 public donID;
    string public sourceCode;
    
    // Order structure (simplified for testing)
    struct Order {
        uint256 id;
        address seller;
        address buyer;
        uint256 amountUSDC;
        uint256 priceBOB;
        OrderStatus status;
        bytes32 chainlinkRequestId;
        uint256 createdAt;
    }
    
    enum OrderStatus {
        Created,
        Accepted,
        PaymentPending,
        PaymentVerified,
        Completed,
        Cancelled,
        Failed
    }
    
    // Storage
    mapping(uint256 => Order) public orders;
    mapping(bytes32 => uint256) public requestIdToOrderId;
    mapping(bytes32 => bool) public pendingRequests;
    uint256 public nextOrderId = 1;
    
    // Events
    event OrderMocked(uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 amountUSDC, uint256 priceBOB);
    event PaymentVerificationRequested(uint256 indexed orderId, bytes32 indexed requestId, string bankingApiUrl);
    event PaymentVerificationCompleted(uint256 indexed orderId, bytes32 indexed requestId, bool verified);
    event PaymentVerificationFailed(uint256 indexed orderId, bytes32 indexed requestId, string reason);
    event OrderStatusChanged(uint256 indexed orderId, OrderStatus oldStatus, OrderStatus newStatus);
    
    // Errors
    error OrderNotFound();
    error OrderNotAccepted();
    error OrderExpired();
    error RequestAlreadyPending();
    error InvalidRequest();
    error UnknownRequest();

    constructor() FunctionsClient(address(0)) {
        // Will be initialized in the deploy script
    }

    function initialize(
        address _router,
        uint64 _subscriptionId,
        bytes32 _donID,
        string memory _sourceCode
    ) external onlyOwner {
        _setRouter(_router);
        subscriptionId = _subscriptionId;
        donID = _donID;
        gasLimit = 300000;
        sourceCode = _sourceCode;
    }

    /**
     * @notice Mock order creation for testing purposes
     * @param seller Seller address
     * @param buyer Buyer address  
     * @param amountUSDC Amount of USDC
     * @param priceBOB Price in BOB currency
     * @return orderId The created order ID
     */
    function mockCreateOrder(
        address seller,
        address buyer,
        uint256 amountUSDC,
        uint256 priceBOB
    ) external returns (uint256 orderId) {
        orderId = nextOrderId++;
        
        orders[orderId] = Order({
            id: orderId,
            seller: seller,
            buyer: buyer,
            amountUSDC: amountUSDC,
            priceBOB: priceBOB,
            status: OrderStatus.Accepted, // Start in Accepted state for testing
            chainlinkRequestId: bytes32(0),
            createdAt: block.timestamp
        });
        
        emit OrderMocked(orderId, seller, buyer, amountUSDC, priceBOB);
        return orderId;
    }

    /**
     * @notice Request payment verification via Chainlink Functions
     * @param orderId Order ID to verify payment for
     * @param bankingApiUrl Banking API URL
     * @param apiKey API key for authentication
     * @param expectedAmount Expected transfer amount
     * @param buyerBankAccount Buyer's bank account identifier
     * @return requestId Chainlink request ID
     */
    function verifyPayment(
        uint256 orderId,
        string memory bankingApiUrl,
        string memory apiKey,
        string memory expectedAmount,
        string memory buyerBankAccount
    ) external returns (bytes32 requestId) {
        Order storage order = orders[orderId];
        
        if (order.seller == address(0)) revert OrderNotFound();
        if (order.status != OrderStatus.Accepted) revert OrderNotAccepted();
        
        // Check if there's already a pending request for this order
        if (order.chainlinkRequestId != bytes32(0) && pendingRequests[order.chainlinkRequestId]) {
            revert RequestAlreadyPending();
        }
        
        // Update order status
        _updateOrderStatus(orderId, OrderStatus.PaymentPending);
        
        // Prepare Chainlink Functions arguments
        string[] memory args = new string[](5);
        args[0] = _uint256ToString(orderId);
        args[1] = bankingApiUrl;
        args[2] = apiKey;
        args[3] = expectedAmount;
        args[4] = buyerBankAccount;
        
        // Create Chainlink Functions request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(sourceCode);
        req.setArgs(args);
        
        // Send request
        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );
        
        // Store request mapping
        order.chainlinkRequestId = requestId;
        requestIdToOrderId[requestId] = orderId;
        pendingRequests[requestId] = true;
        
        emit PaymentVerificationRequested(orderId, requestId, bankingApiUrl);
        
        return requestId;
    }

    /**
     * @notice Chainlink Functions callback
     * @param requestId Request ID
     * @param response Response data
     * @param err Error data
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        // Verify this is a known request
        uint256 orderId = requestIdToOrderId[requestId];
        if (orderId == 0) {
            revert UnknownRequest();
        }
        
        Order storage order = orders[orderId];
        
        // Mark request as no longer pending
        pendingRequests[requestId] = false;
        
        // Handle errors
        if (err.length > 0) {
            _updateOrderStatus(orderId, OrderStatus.Failed);
            emit PaymentVerificationFailed(orderId, requestId, string(err));
            return;
        }
        
        // Decode response
        uint256 result = abi.decode(response, (uint256));
        bool verified = (result == 1);
        
        if (verified) {
            _updateOrderStatus(orderId, OrderStatus.PaymentVerified);
        } else {
            _updateOrderStatus(orderId, OrderStatus.Accepted); // Reset to accepted
        }
        
        emit PaymentVerificationCompleted(orderId, requestId, verified);
    }

    /**
     * @notice Manual completion for testing (simulates UserOp execution)
     * @param orderId Order ID to complete
     */
    function mockCompleteOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        
        if (order.seller == address(0)) revert OrderNotFound();
        require(order.status == OrderStatus.PaymentVerified, "Payment not verified");
        
        _updateOrderStatus(orderId, OrderStatus.Completed);
    }

    /**
     * @notice Get order details
     * @param orderId Order ID
     * @return order Order struct
     */
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    /**
     * @notice Get order status
     * @param orderId Order ID
     * @return status Order status
     */
    function getOrderStatus(uint256 orderId) external view returns (OrderStatus) {
        return orders[orderId].status;
    }

    /**
     * @notice Check if request is pending
     * @param requestId Request ID
     * @return pending Whether request is pending
     */
    function isRequestPending(bytes32 requestId) external view returns (bool) {
        return pendingRequests[requestId];
    }

    // Internal helper functions
    function _updateOrderStatus(uint256 orderId, OrderStatus newStatus) internal {
        Order storage order = orders[orderId];
        OrderStatus oldStatus = order.status;
        order.status = newStatus;
        
        emit OrderStatusChanged(orderId, oldStatus, newStatus);
    }

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

    // Admin functions
    function updateSourceCode(string memory _sourceCode) external onlyOwner {
        sourceCode = _sourceCode;
    }

    function updateGasLimit(uint32 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    function updateSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    function updateDonID(bytes32 _donID) external onlyOwner {
        donID = _donID;
    }

    receive() external payable {}
}

/**
 * @title MockFunctionsRouter
 * @notice Mock router for testing Chainlink Functions locally
 */
contract MockFunctionsRouter {
    mapping(address => bool) public allowedSenders;
    
    event RequestSent(bytes32 indexed requestId, address indexed sender);
    event ResponseSent(bytes32 indexed requestId, bytes response, bytes err);
    
    modifier onlyAllowedSender() {
        require(allowedSenders[msg.sender], "Sender not allowed");
        _;
    }
    
    function addAllowedSender(address sender) external {
        allowedSenders[sender] = true;
    }
    
    function sendRequest(
        uint64, // subscriptionId
        bytes calldata, // data
        uint16, // dataVersion
        uint32, // callbackGasLimit
        bytes32 // donID
    ) external onlyAllowedSender returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(block.timestamp, msg.sender, block.prevrandao));
        
        emit RequestSent(requestId, msg.sender);
        
        return requestId;
    }
    
    // Mock fulfill function for testing
    function fulfillRequest(
        address consumer,
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        emit ResponseSent(requestId, response, err);
        
        // Call the consumer's fulfillRequest function
        (bool success,) = consumer.call(
            abi.encodeWithSignature(
                "handleOracleFulfillment(bytes32,bytes,bytes)",
                requestId,
                response,
                err
            )
        );
        
        require(success, "Consumer call failed");
    }
}