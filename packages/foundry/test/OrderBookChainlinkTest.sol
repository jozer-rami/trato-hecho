// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouter} from "foundry-chainlink-toolkit/contracts/v0.8.19/FunctionsRouter.sol";
import {OrderBookChainlinkTest} from "../contracts/OrderBookChainlinkTest.sol";

/**
 * @title Enhanced OrderBook Test Suite with Chainlink Integration
 * @notice Comprehensive testing using foundry-chainlink-toolkit for realistic Chainlink integration
 * @dev Uses real Chainlink infrastructure in a local testing environment
 */
contract OrderBookChainlinkTestSuite is Test {
    // Contracts
    OrderBookChainlinkTest public orderBook;
    FunctionsRouter public functionsRouter;
    
    // Test addresses
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public owner = makeAddr("owner");
    
    // Test constants
    uint256 public constant TEST_AMOUNT_USDC = 100_000000; // 100 USDC (6 decimals)
    uint256 public constant TEST_PRICE_BOB = 500 ether; // 500 BOB
    string public constant TEST_API_URL = "https://api.bank.com";
    string public constant TEST_API_KEY = "test_api_key_12345";
    string public constant TEST_EXPECTED_AMOUNT = "500";
    string public constant TEST_BUYER_ACCOUNT = "buyer_account_123";
    
    // Enhanced JavaScript source code for Chainlink Functions
    string public constant ENHANCED_SOURCE_CODE = 
        "const orderId = args[0];"
        "const bankingApiUrl = args[1];"
        "const apiKey = args[2];"
        "const expectedAmount = args[3];"
        "const buyerBankAccount = args[4];"
        "const timestamp = args[5];"
        ""
        "console.log(`Processing payment verification for order ${orderId}`);"
        ""
        "if (!orderId || !bankingApiUrl || !apiKey) {"
        "  throw Error('Missing required arguments');"
        "}"
        ""
        "const apiResponse = await Functions.makeHttpRequest({"
        "  url: `${bankingApiUrl}/api/v1/transfers/verify`,"
        "  method: 'POST',"
        "  headers: {"
        "    'Authorization': `Bearer ${apiKey}`," 
        "    'Content-Type': 'application/json'"
        "  },"
        "  data: {"
        "    orderId: orderId,"
        "    expectedAmount: expectedAmount,"
        "    buyerAccount: buyerBankAccount,"
        "    timestamp: timestamp"
        "  }"
        "});"
        ""
        "if (apiResponse.error) {"
        "  console.error('Banking API error:', apiResponse.error);"
        "  throw Error(`Banking API error: ${apiResponse.error}`);"
        "}"
        ""
        "const responseData = apiResponse.data;"
        ""
        "if (!responseData || typeof responseData.confirmed !== 'boolean') {"
        "  throw Error('Invalid API response format');"
        "}"
        ""
        "const isValidTransfer = responseData.confirmed && "
        "                       responseData.orderId === orderId &&"
        "                       responseData.amount >= parseFloat(expectedAmount);"
        ""
        "console.log(`Payment verification result: ${isValidTransfer}`);"
        ""
        "return Functions.encodeUint256(isValidTransfer ? 1 : 0);";

    function setUp() public {
        console.log("=== Setting up Enhanced OrderBook Test Suite ===");
        
        // Setup Chainlink infrastructure
        _setupChainlinkInfrastructure();
        
        // Deploy and configure OrderBook
        _deployOrderBook();
        
        // Fund test accounts
        _fundTestAccounts();
        
        console.log("Setup completed successfully");
    }

    /**
     * @notice Setup Chainlink infrastructure
     * @dev Creates a realistic local Chainlink environment
     */
    function _setupChainlinkInfrastructure() internal {
        console.log("Setting up Chainlink infrastructure...");
        
        // Deploy Functions Router
        functionsRouter = new FunctionsRouter();
        
        console.log("Functions Router deployed at:", address(functionsRouter));
    }

    /**
     * @notice Deploy and initialize OrderBook contract
     */
    function _deployOrderBook() internal {
        console.log("Deploying OrderBook contract...");
        
        vm.startPrank(owner);
        
        // Deploy OrderBook
        orderBook = new OrderBookChainlinkTest();
        
        // Initialize with Chainlink configuration
        orderBook.initialize(
            address(functionsRouter),
            1, // subscriptionId
            keccak256("test-don"), // donID
            ENHANCED_SOURCE_CODE
        );
        
        vm.stopPrank();
        
        console.log("OrderBook deployed at:", address(orderBook));
    }

    /**
     * @notice Fund test accounts with ETH
     */
    function _fundTestAccounts() internal {
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
        vm.deal(owner, 10 ether);
    }

    // ============ Enhanced Order Creation Tests ============
    
    function test_EnhancedCreateOrder() public {
        uint256 deadline = block.timestamp + 3600; // 1 hour from now
        
        vm.expectEmit(true, true, true, true);
        emit OrderBookChainlinkTest.OrderMocked(1, alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        uint256 orderId = orderBook.mockCreateOrder(
            alice, 
            bob, 
            TEST_AMOUNT_USDC, 
            TEST_PRICE_BOB,
            deadline
        );
        
        assertEq(orderId, 1);
        
        OrderBookChainlinkTest.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.id, 1);
        assertEq(order.seller, alice);
        assertEq(order.buyer, bob);
        assertEq(order.amountUSDC, TEST_AMOUNT_USDC);
        assertEq(order.priceBOB, TEST_PRICE_BOB);
        assertEq(order.deadline, deadline);
        assertEq(uint8(order.status), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
        assertGt(order.createdAt, 0);
    }

    function test_CreateOrder_ValidationErrors() public {
        uint256 deadline = block.timestamp + 3600;
        
        // Test zero seller address
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Seller cannot be zero address"));
        orderBook.mockCreateOrder(address(0), bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Test zero buyer address
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Buyer cannot be zero address"));
        orderBook.mockCreateOrder(alice, address(0), TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Test zero amount
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Amount must be greater than zero"));
        orderBook.mockCreateOrder(alice, bob, 0, TEST_PRICE_BOB, deadline);
        
        // Test past deadline
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Deadline must be in the future"));
        orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, block.timestamp - 1);
    }

    // ============ Enhanced Payment Verification Tests ============
    
    function test_VerifyPayment_WithRealChainlink() public {
        // Create order
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Request payment verification
        vm.expectEmit(true, true, false, false);
        emit OrderBookChainlinkTest.PaymentVerificationRequested(orderId, bytes32(0), TEST_API_URL, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT, block.timestamp);
        
        bytes32 requestId = orderBook.verifyPayment(
            orderId,
            TEST_API_URL,
            TEST_API_KEY,
            TEST_EXPECTED_AMOUNT,
            TEST_BUYER_ACCOUNT
        );
        
        // Verify request was created
        assertNotEq(requestId, bytes32(0));
        assertTrue(orderBook.isRequestPending(requestId));
        
        // Check order status updated
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentPending));
        
        // Verify request metadata
        OrderBookChainlinkTest.RequestMetadata memory metadata = orderBook.getRequestMetadata(requestId);
        assertEq(metadata.orderId, orderId);
        assertEq(metadata.requester, address(this));
        assertEq(metadata.bankingApiUrl, TEST_API_URL);
        assertEq(metadata.expectedAmount, TEST_EXPECTED_AMOUNT);
        assertFalse(metadata.fulfilled);
        
        console.log("Payment verification request created with ID:", vm.toString(requestId));
    }

    function test_VerifyPayment_ValidationErrors() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Test non-existent order
        vm.expectRevert(abi.encodeWithSignature("OrderNotFound(uint256)", 999));
        orderBook.verifyPayment(999, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        // Test empty banking API URL
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Banking API URL required"));
        orderBook.verifyPayment(orderId, "", TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        // Test empty API key
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "API key required"));
        orderBook.verifyPayment(orderId, TEST_API_URL, "", TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        // Test empty expected amount
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Expected amount required"));
        orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, "", TEST_BUYER_ACCOUNT);
    }

    function test_VerifyPayment_ExpiredOrder() public {
        // Create order with short deadline
        uint256 shortDeadline = block.timestamp + 60; // 1 minute
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, shortDeadline);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 120);
        
        // Should revert with order expired
        vm.expectRevert(abi.encodeWithSignature("OrderExpired(uint256,uint256,uint256)", orderId, shortDeadline, block.timestamp));
        orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
    }

    function test_VerifyPayment_DuplicateRequest() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // First request should succeed
        bytes32 requestId1 = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        // Second request should fail
        vm.expectRevert(abi.encodeWithSignature("RequestAlreadyPending(uint256,bytes32)", orderId, requestId1));
        orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
    }

    // ============ Chainlink Functions Fulfillment Tests ============
    
    function test_FulfillRequest_PaymentVerified_WithRealChainlink() public {
        // Setup and create verification request
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        // Execute Chainlink Functions request
        vm.expectEmit(true, true, false, false);
        emit OrderBookChainlinkTest.PaymentVerificationCompleted(orderId, requestId, true, 0, "");
        
        // Simulate successful fulfillment
        bytes memory response = abi.encode(uint256(1)); // 1 = verified
        orderBook._fulfillRequest(requestId, response, "");
        
        // Verify final state
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentVerified));
        assertFalse(orderBook.isRequestPending(requestId));
        
        // Check metadata was updated
        OrderBookChainlinkTest.RequestMetadata memory metadata = orderBook.getRequestMetadata(requestId);
        assertTrue(metadata.fulfilled);
        assertGt(metadata.gasUsed, 0);
        
        console.log("Payment verification completed successfully");
        console.log("Gas used for fulfillment:", metadata.gasUsed);
    }

    function test_FulfillRequest_PaymentNotVerified() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        vm.expectEmit(true, true, false, false);
        emit OrderBookChainlinkTest.PaymentVerificationCompleted(orderId, requestId, false, 0, "");
        
        // Simulate failed verification
        bytes memory response = abi.encode(uint256(0)); // 0 = not verified
        orderBook._fulfillRequest(requestId, response, "");
        
        // Order should reset to Accepted state for retry
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
        assertFalse(orderBook.isRequestPending(requestId));
    }

    function test_FulfillRequest_APIError() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        vm.expectEmit(true, true, false, false);
        emit OrderBookChainlinkTest.PaymentVerificationFailed(orderId, requestId, "Connection timeout", "");
        
        // Simulate API error
        bytes memory error = abi.encode("Connection timeout");
        orderBook._fulfillRequest(requestId, "", error);
        
        // Order should be marked as failed
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Failed));
        assertFalse(orderBook.isRequestPending(requestId));
    }

    function test_FulfillRequest_InvalidResponseFormat() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        vm.expectEmit(true, true, false, false);
        emit OrderBookChainlinkTest.PaymentVerificationFailed(orderId, requestId, "Invalid API response format", "");
        
        // Simulate invalid response
        bytes memory response = abi.encode("invalid");
        orderBook._fulfillRequest(requestId, response, "");
        
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Failed));
    }

    // ============ Order Completion Tests ============
    
    function test_CompleteOrder_Success() public {
        // Full workflow test
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Verify payment
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        bytes memory response = abi.encode(uint256(1));
        orderBook._fulfillRequest(requestId, response, "");
        
        // Complete order
        vm.expectEmit(true, true, true, true);
        emit OrderBookChainlinkTest.OrderCompleted(orderId, alice, bob, TEST_AMOUNT_USDC);
        
        orderBook.mockCompleteOrder(orderId);
        
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Completed));
    }

    function test_CompleteOrder_PaymentNotVerified() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        vm.expectRevert(abi.encodeWithSignature("InvalidRequest(string)", "Payment not verified"));
        orderBook.mockCompleteOrder(orderId);
    }

    function test_CompleteOrder_ExpiredOrder() public {
        uint256 shortDeadline = block.timestamp + 60;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, shortDeadline);
        
        // Verify payment
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        bytes memory response = abi.encode(uint256(1));
        orderBook._fulfillRequest(requestId, response, "");
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 120);
        
        vm.expectRevert(abi.encodeWithSignature("OrderExpired(uint256,uint256,uint256)", orderId, shortDeadline, block.timestamp));
        orderBook.mockCompleteOrder(orderId);
    }

    // ============ Advanced Integration Tests ============
    
    function test_MultipleOrdersWorkflow() public {
        uint256 deadline = block.timestamp + 3600;
        
        // Create multiple orders
        uint256 orderId1 = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        uint256 orderId2 = orderBook.mockCreateOrder(bob, charlie, TEST_AMOUNT_USDC * 2, TEST_PRICE_BOB * 2, deadline);
        uint256 orderId3 = orderBook.mockCreateOrder(charlie, alice, TEST_AMOUNT_USDC / 2, TEST_PRICE_BOB / 2, deadline);
        
        // Setup different responses
        bytes32 requestId1 = orderBook.verifyPayment(orderId1, TEST_API_URL, TEST_API_KEY, "500", TEST_BUYER_ACCOUNT);
        bytes32 requestId2 = orderBook.verifyPayment(orderId2, TEST_API_URL, TEST_API_KEY, "1000", TEST_BUYER_ACCOUNT);
        bytes32 requestId3 = orderBook.verifyPayment(orderId3, TEST_API_URL, TEST_API_KEY, "250", TEST_BUYER_ACCOUNT);
        
        // Fulfill all requests
        orderBook._fulfillRequest(requestId1, abi.encode(uint256(1)), ""); // Success
        orderBook._fulfillRequest(requestId2, abi.encode(uint256(0)), ""); // Failed
        orderBook._fulfillRequest(requestId3, "", abi.encode("API timeout")); // Error
        
        // Check final states
        assertEq(uint8(orderBook.getOrderStatus(orderId1)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentVerified));
        assertEq(uint8(orderBook.getOrderStatus(orderId2)), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
        assertEq(uint8(orderBook.getOrderStatus(orderId3)), uint8(OrderBookChainlinkTest.OrderStatus.Failed));
        
        // Complete successful order
        orderBook.mockCompleteOrder(orderId1);
        assertEq(uint8(orderBook.getOrderStatus(orderId1)), uint8(OrderBookChainlinkTest.OrderStatus.Completed));
    }

    function test_GasUsageOptimization() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Measure gas for verification request
        uint256 gasStart = gasleft();
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        uint256 gasUsedForRequest = gasStart - gasleft();
        
        console.log("Gas used for payment verification request:", gasUsedForRequest);
        
        // Fulfill and measure gas for completion
        orderBook._fulfillRequest(requestId, abi.encode(uint256(1)), "");
        
        OrderBookChainlinkTest.RequestMetadata memory metadata = orderBook.getRequestMetadata(requestId);
        console.log("Gas used for fulfillment:", metadata.gasUsed);
        
        // Verify gas usage is reasonable
        assertLt(gasUsedForRequest, 300000, "Request gas usage too high");
        assertGt(metadata.gasUsed, 0, "Fulfillment should use gas");
    }

    function test_EventEmissionAndLogging() public {
        uint256 deadline = block.timestamp + 3600;
        
        // Test order creation events
        vm.recordLogs();
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("OrderMocked(uint256,address,address,uint256,uint256,uint256)"));
        
        // Test verification request events
        vm.recordLogs();
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        logs = vm.getRecordedLogs();
        assertGt(logs.length, 0);
        
        // Test fulfillment events
        vm.recordLogs();
        orderBook._fulfillRequest(requestId, abi.encode(uint256(1)), "");
        
        logs = vm.getRecordedLogs();
        assertGt(logs.length, 0);
        
        console.log("All events emitted correctly");
    }

    // ============ Admin Function Tests ============
    
    function test_AdminFunctions() public {
        vm.startPrank(owner);
        
        // Test source code update
        string memory newSourceCode = "console.log('updated');";
        vm.expectEmit(false, false, false, true);
        emit OrderBookChainlinkTest.SourceCodeUpdated(ENHANCED_SOURCE_CODE, newSourceCode);
        orderBook.updateSourceCode(newSourceCode);
        assertEq(orderBook.sourceCode(), newSourceCode);
        
        // Test gas limit update
        uint32 newGasLimit = 500000;
        vm.expectEmit(false, false, false, true);
        emit OrderBookChainlinkTest.GasLimitUpdated(300000, newGasLimit);
        orderBook.updateGasLimit(newGasLimit);
        assertEq(orderBook.gasLimit(), newGasLimit);
        
        // Test subscription ID update
        uint64 newSubscriptionId = 999;
        vm.expectEmit(false, false, false, true);
        emit OrderBookChainlinkTest.SubscriptionIdUpdated(1, newSubscriptionId);
        orderBook.updateSubscriptionId(newSubscriptionId);
        assertEq(orderBook.subscriptionId(), newSubscriptionId);
        
        vm.stopPrank();
    }

    function test_AdminFunctions_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        orderBook.updateSourceCode("new code");
        
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        orderBook.updateGasLimit(500000);
    }

    // ============ View Functions Tests ============
    
    function test_ViewFunctions() public {
        uint256 deadline = block.timestamp + 3600;
        uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
        
        // Test getOrder
        OrderBookChainlinkTest.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.seller, alice);
        assertEq(order.buyer, bob);
        
        // Test getOrderStatus
        assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
        
        // Test getAllOrders
        uint256[] memory orderIds = orderBook.getAllOrders(10);
        assertEq(orderIds.length, 1);
        assertEq(orderIds[0], 1);
        
        // Test after verification request
        bytes32 requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
        assertTrue(orderBook.isRequestPending(requestId));
        
        (bytes32 returnedRequestId, bool pending, OrderBookChainlinkTest.RequestMetadata memory metadata) = orderBook.getOrderRequest(orderId);
        assertEq(returnedRequestId, requestId);
        assertTrue(pending);
        assertEq(metadata.orderId, orderId);
        assertEq(metadata.bankingApiUrl, TEST_API_URL);
    }

    // ============ Helper Functions ============
    
    /**
     * @notice Helper to create order with default values
     */
    function _createDefaultOrder() internal returns (uint256 orderId) {
        uint256 deadline = block.timestamp + 3600;
        return orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB, deadline);
    }

    /**
     * @notice Helper to create and verify order
     */
    function _createAndVerifyOrder() internal returns (uint256 orderId, bytes32 requestId) {
        orderId = _createDefaultOrder();
        requestId = orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
    }
}