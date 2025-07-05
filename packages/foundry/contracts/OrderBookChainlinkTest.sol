// packages/foundry/contracts/OrderBookChainlinkTest.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * @title OrderBookChainlinkTest - Corrected P2P Flow
 * @notice P2P exchange where sellers create orders and unknown buyers accept them
 * @dev Fixed to follow proper P2P marketplace pattern
 */
contract OrderBookChainlinkTest is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // ============ Basic Configuration ============
    address public owner;
    uint64 public subscriptionId;

    // Hardcoded Chainlink configuration (Arbitrum Sepolia)
    address constant router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    uint32 constant gasLimit = 3000000;
    bytes32 constant donID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;

    // ============ Order Management ============
    struct Order {
        uint256 id;
        address seller;         // ✅ Known: person creating the order
        address buyer;          // ✅ Initially address(0), set when someone accepts
        uint256 amountUSDC;     // ✅ How much USDC seller wants to sell
        uint256 priceBOB;       // ✅ How much BOB seller wants in return
        OrderStatus status;
        uint256 createdAt;
        uint256 deadline;
    }
    
    enum OrderStatus {
        Created,        // ✅ Seller posted order, no buyer yet
        Accepted,       // ✅ Someone accepted and became the buyer
        PaymentPending, // ✅ Buyer payment verification in progress
        PaymentVerified,// ✅ Chainlink confirmed buyer paid
        Completed,      // ✅ USDC transferred to buyer
        Cancelled,      // ✅ Seller cancelled before acceptance
        Expired,        // ✅ Order expired
        Failed          // ✅ Payment verification failed
    }

    // ============ Request Tracking ============
    struct RequestIdentity {
        uint256 orderId;
        address requester;
        string bankingApiUrl;
        string expectedAmount;
    }

    mapping(uint256 => Order) public orders;
    mapping(bytes32 => RequestIdentity) public requestToOrder;
    bytes32[] public requestIds;
    uint256 public nextOrderId = 1;

    // ============ JavaScript Source ============
    string public source = 
        "const orderId = args[0];"
        "const bankingApiUrl = args[1];"
        "const expectedAmount = args[2];"
        "const buyerAccount = args[3];"
        ""
        "if (!secrets.apiKey) {"
        "  throw Error('Missing API key');"
        "};"
        ""
        "const apiRequest = Functions.makeHttpRequest({"
        "  url: bankingApiUrl + '/api/v1/transfers/verify',"
        "  method: 'POST',"
        "  headers: {"
        "    'Authorization': 'Bearer ' + secrets.apiKey,"
        "    'Content-Type': 'application/json'"
        "  },"
        "  data: {"
        "    orderId: orderId,"
        "    expectedAmount: expectedAmount,"
        "    buyerAccount: buyerAccount"
        "  }"
        "});"
        ""
        "const apiResponse = await apiRequest;"
        ""
        "if (apiResponse.error) {"
        "  throw Error('Banking API request failed');"
        "};"
        ""
        "const responseData = apiResponse.data;"
        "const result = (responseData.confirmed && "
        "               responseData.orderId == orderId && "
        "               responseData.amount >= parseFloat(expectedAmount)) ? 1 : 0;"
        ""
        "return Functions.encodeUint256(result);";

    // ============ Events ============
    event OrderCreated(uint256 indexed orderId, address indexed seller, uint256 amountUSDC, uint256 priceBOB);
    event OrderAccepted(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event PaymentVerificationRequested(uint256 indexed orderId, bytes32 indexed requestId, address indexed buyer);
    event PaymentVerified(uint256 indexed orderId, bool verified);
    event OrderCompleted(uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 amount);
    event OrderCancelled(uint256 indexed orderId, address indexed seller);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint64 _subscriptionId) FunctionsClient(router) {
        owner = msg.sender;
        subscriptionId = _subscriptionId;
    }

    // ============ CORRECTED Order Flow ============

    /**
     * @notice Seller creates an order to sell USDC for BOB
     * @dev CORRECTED: Only seller is known, buyer is address(0) initially
     * @param amountUSDC Amount of USDC seller wants to sell
     * @param priceBOB Amount of BOB seller wants to receive
     * @param deadline When this order expires
     */
    function createSellOrder(
        uint256 amountUSDC,
        uint256 priceBOB,
        uint256 deadline
    ) external returns (uint256 orderId) {
        require(amountUSDC > 0 && priceBOB > 0, "Invalid amounts");
        require(deadline > block.timestamp, "Invalid deadline");

        orderId = nextOrderId++;
        
        orders[orderId] = Order({
            id: orderId,
            seller: msg.sender,        // ✅ Known: caller is the seller
            buyer: address(0),         // ✅ Unknown: no buyer yet
            amountUSDC: amountUSDC,
            priceBOB: priceBOB,
            status: OrderStatus.Created,
            createdAt: block.timestamp,
            deadline: deadline
        });

        emit OrderCreated(orderId, msg.sender, amountUSDC, priceBOB);
    }

    /**
     * @notice Anyone can accept a created order and become the buyer
     * @dev CORRECTED: This is where buyer gets set
     * @param orderId The order to accept
     */
    function acceptOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.id != 0, "Order not found");
        require(order.status == OrderStatus.Created, "Order not available");
        require(block.timestamp <= order.deadline, "Order expired");
        require(msg.sender != order.seller, "Seller cannot accept own order");

        // ✅ NOW we know who the buyer is
        order.buyer = msg.sender;
        order.status = OrderStatus.Accepted;

        emit OrderAccepted(orderId, msg.sender, order.seller);
    }

    /**
     * @notice Buyer verifies they have made the payment
     * @dev Only the buyer can trigger payment verification
     */
    function verifyPayment(
        uint256 orderId,
        string calldata bankingApiUrl,
        string calldata expectedAmount,
        string calldata buyerAccount
    ) external returns (bytes32 requestId) {
        Order storage order = orders[orderId];
        require(order.id != 0, "Order not found");
        require(order.status == OrderStatus.Accepted, "Order not accepted yet");
        require(msg.sender == order.buyer, "Only buyer can verify payment");
        require(block.timestamp <= order.deadline, "Order expired");

        // Update status
        order.status = OrderStatus.PaymentPending;

        // Send Chainlink request
        requestId = initializeFunctionsRequest(
            orderId,
            bankingApiUrl,
            expectedAmount,
            buyerAccount,
            1, // secrets version
            msg.sender
        );

        emit PaymentVerificationRequested(orderId, requestId, msg.sender);
    }

    /**
     * @notice Complete order - seller transfers USDC to buyer
     * @dev Only seller can complete after payment verification
     */
    function completeOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.id != 0, "Order not found");
        require(order.status == OrderStatus.PaymentVerified, "Payment not verified");
        require(msg.sender == order.seller, "Only seller can complete order");

        order.status = OrderStatus.Completed;
        
        // 💡 In a real implementation, this would transfer USDC tokens
        // IERC20(usdcToken).transferFrom(order.seller, order.buyer, order.amountUSDC);
        
        emit OrderCompleted(orderId, order.seller, order.buyer, order.amountUSDC);
    }

    /**
     * @notice Seller can cancel their order before it's accepted
     */
    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.id != 0, "Order not found");
        require(msg.sender == order.seller, "Only seller can cancel");
        require(order.status == OrderStatus.Created, "Can only cancel non-accepted orders");

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(orderId, order.seller);
    }

   

    // ============ Chainlink Functions Implementation ============

    function initializeFunctionsRequest(
        uint256 orderId,
        string memory bankingApiUrl,
        string memory expectedAmount,
        string memory buyerAccount,
        uint64 donHostedSecretsVersion,
        address caller
    ) internal returns (bytes32) {
        FunctionsRequest.Request memory req;
        
        string[] memory args = new string[](4);
        args[0] = uint256ToString(orderId);
        args[1] = bankingApiUrl;
        args[2] = expectedAmount;
        args[3] = buyerAccount;

        if (args.length > 0) req.setArgs(args);
        req.initializeRequestForInlineJavaScript(source);
        req.addDONHostedSecrets(0, donHostedSecretsVersion);

        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        requestToOrder[requestId] = RequestIdentity(
            orderId,
            caller,
            bankingApiUrl,
            expectedAmount
        );

        return requestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        RequestIdentity memory identity = requestToOrder[requestId];
        require(identity.orderId != 0, "Request not found");

        Order storage order = orders[identity.orderId];

        if (err.length > 0) {
            order.status = OrderStatus.Failed;
            emit PaymentVerified(identity.orderId, false);
            return;
        }

        require(uint256(bytes32(response)) == 1, "Payment not verified");

        order.status = OrderStatus.PaymentVerified;
        emit PaymentVerified(identity.orderId, true);
    }

    // ============ Standard Functions ============

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getOrderStatus(uint256 orderId) external view returns (OrderStatus) {
        return orders[orderId].status;
    }

    function updateSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    function updateSource(string memory _source) external onlyOwner {
        source = _source;
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
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

    // ============ Mock Functions for Testing ============

    // /**
    //  * @notice Mock function to create and accept order in one step (for testing)
    //  */
    // function mockCreateAcceptedOrder(
    //     address seller,
    //     address buyer,
    //     uint256 amountUSDC,
    //     uint256 priceBOB,
    //     uint256 deadline
    // ) external returns (uint256 orderId) {
    //     // Seller creates order
    //     vm.prank(seller);
    //     orderId = this.createSellOrder(amountUSDC, priceBOB, deadline);
        
    //     // Buyer accepts order
    //     vm.prank(buyer);
    //     this.acceptOrder(orderId);
        
    //     return orderId;
    // }

     // ============ View Functions for Marketplace ============

    /**
     * @notice Get all available orders (for buyers to browse)
     * @dev Returns orders that can still be accepted
     */
    function getAvailableOrders(uint256 limit) external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256 totalOrders = nextOrderId - 1;
        
        // Count available orders
        for (uint256 i = 1; i <= totalOrders && count < limit; i++) {
            if (orders[i].status == OrderStatus.Created && 
                block.timestamp <= orders[i].deadline) {
                count++;
            }
        }
        
        orderIds = new uint256[](count);
        uint256 index = 0;
        
        // Fill array with available order IDs (newest first)
        for (uint256 i = totalOrders; i >= 1 && index < count; i--) {
            if (orders[i].status == OrderStatus.Created && 
                block.timestamp <= orders[i].deadline) {
                orderIds[index] = i;
                index++;
            }
        }
    }

    /**
     * @notice Get orders by seller (for sellers to manage their orders)
     */
    function getOrdersBySeller(address seller, uint256 limit) external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256 totalOrders = nextOrderId - 1;
        
        // Count seller's orders
        for (uint256 i = 1; i <= totalOrders && count < limit; i++) {
            if (orders[i].seller == seller) {
                count++;
            }
        }
        
        orderIds = new uint256[](count);
        uint256 index = 0;
        
        // Fill array
        for (uint256 i = totalOrders; i >= 1 && index < count; i--) {
            if (orders[i].seller == seller) {
                orderIds[index] = i;
                index++;
            }
        }
    }

    /**
     * @notice Get orders by buyer (for buyers to track their purchases)
     */
    function getOrdersByBuyer(address buyer, uint256 limit) external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256 totalOrders = nextOrderId - 1;
        
        // Count buyer's orders
        for (uint256 i = 1; i <= totalOrders && count < limit; i++) {
            if (orders[i].buyer == buyer) {
                count++;
            }
        }
        
        orderIds = new uint256[](count);
        uint256 index = 0;
        
        // Fill array
        for (uint256 i = totalOrders; i >= 1 && index < count; i--) {
            if (orders[i].buyer == buyer) {
                orderIds[index] = i;
                index++;
            }
        }
    }
}