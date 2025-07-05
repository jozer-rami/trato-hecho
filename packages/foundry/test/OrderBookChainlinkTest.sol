
// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "../contracts/OrderBookChainlinkTest.sol";

// contract OrderBookChainlinkTestSuite is Test {
//     OrderBookChainlinkTest public orderBook;
//     MockFunctionsRouter public mockRouter;
    
//     // Test addresses
//     address public alice = makeAddr("alice");
//     address public bob = makeAddr("bob");
//     address public owner = makeAddr("owner");
    
//     // Test constants
//     uint256 public constant TEST_AMOUNT_USDC = 100_000000; // 100 USDC (6 decimals)
//     uint256 public constant TEST_PRICE_BOB = 500 ether; // 500 BOB
//     string public constant TEST_API_URL = "https://api.bank.com";
//     string public constant TEST_API_KEY = "test_api_key_12345";
//     string public constant TEST_EXPECTED_AMOUNT = "500";
//     string public constant TEST_BUYER_ACCOUNT = "buyer_account_123";
//     string public constant SOURCE_CODE = "test_source_code";

//     function setUp() public {
//         vm.startPrank(owner);
        
//         // Deploy contracts
//         mockRouter = new MockFunctionsRouter();
//         orderBook = new OrderBookChainlinkTest();
        
//         // Initialize OrderBook
//         orderBook.initialize(
//             address(mockRouter),
//             1, // subscriptionId
//             keccak256("test-don"), // donID
//             SOURCE_CODE
//         );
        
//         // Configure mock router
//         mockRouter.addAllowedSender(address(orderBook));
        
//         vm.stopPrank();
//     }

//     // ============ Basic Functionality Tests ============
    
//     function test_MockCreateOrder() public {
//         vm.expectEmit(true, true, true, true);
//         emit OrderBookChainlinkTest.OrderMocked(1, alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
        
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
        
//         assertEq(orderId, 1);
        
//         OrderBookChainlinkTest.Order memory order = orderBook.getOrder(orderId);
//         assertEq(order.id, 1);
//         assertEq(order.seller, alice);
//         assertEq(order.buyer, bob);
//         assertEq(order.amountUSDC, TEST_AMOUNT_USDC);
//         assertEq(order.priceBOB, TEST_PRICE_BOB);
//         assertEq(uint8(order.status), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
//     }

//     function test_VerifyPayment_Success() public {
//         // Create order first
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
        
//         // Verify payment
//         vm.expectEmit(true, true, false, false);
//         emit OrderBookChainlinkTest.PaymentVerificationRequested(orderId, bytes32(0), TEST_API_URL);
        
//         bytes32 requestId = orderBook.verifyPayment(
//             orderId,
//             TEST_API_URL,
//             TEST_API_KEY,
//             TEST_EXPECTED_AMOUNT,
//             TEST_BUYER_ACCOUNT
//         );
        
//         // Verify results
//         assertNotEq(requestId, bytes32(0));
//         assertTrue(orderBook.isRequestPending(requestId));
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentPending));
//     }

//     function test_FulfillRequest_PaymentVerified() public {
//         // Setup: Create order and verification request
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
//         bytes32 requestId = orderBook.verifyPayment(
//             orderId,
//             TEST_API_URL,
//             TEST_API_KEY,
//             TEST_EXPECTED_AMOUNT,
//             TEST_BUYER_ACCOUNT
//         );
        
//         // Act: Simulate successful payment verification
//         bytes memory response = abi.encode(uint256(1)); // 1 = verified
        
//         vm.expectEmit(true, true, false, true);
//         emit OrderBookChainlinkTest.PaymentVerificationCompleted(orderId, requestId, true);
        
//         mockRouter.fulfillRequest(address(orderBook), requestId, response, "");
        
//         // Assert: Check final state
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentVerified));
//         assertFalse(orderBook.isRequestPending(requestId));
//     }

//     function test_FulfillRequest_PaymentNotVerified() public {
//         // Setup
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
//         bytes32 requestId = orderBook.verifyPayment(
//             orderId,
//             TEST_API_URL,
//             TEST_API_KEY,
//             TEST_EXPECTED_AMOUNT,
//             TEST_BUYER_ACCOUNT
//         );
        
//         // Act: Simulate payment not found
//         bytes memory response = abi.encode(uint256(0)); // 0 = not verified
//         mockRouter.fulfillRequest(address(orderBook), requestId, response, "");
        
//         // Assert: Order should reset to Accepted state
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
//         assertFalse(orderBook.isRequestPending(requestId));
//     }

//     function test_FulfillRequest_Error() public {
//         // Setup
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
//         bytes32 requestId = orderBook.verifyPayment(
//             orderId,
//             TEST_API_URL,
//             TEST_API_KEY,
//             TEST_EXPECTED_AMOUNT,
//             TEST_BUYER_ACCOUNT
//         );
        
//         // Act: Simulate API error
//         bytes memory err = abi.encode("Banking API error: Connection timeout");
        
//         vm.expectEmit(true, true, false, false);
//         emit OrderBookChainlinkTest.PaymentVerificationFailed(orderId, requestId, "Banking API error: Connection timeout");
        
//         mockRouter.fulfillRequest(address(orderBook), requestId, "", err);
        
//         // Assert: Order should be marked as failed
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Failed));
//     }

//     function test_FullWorkflow_Success() public {
//         // 1. Create order
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Accepted));
        
//         // 2. Request payment verification
//         bytes32 requestId = orderBook.verifyPayment(
//             orderId,
//             TEST_API_URL,
//             TEST_API_KEY,
//             TEST_EXPECTED_AMOUNT,
//             TEST_BUYER_ACCOUNT
//         );
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentPending));
        
//         // 3. Chainlink responds with success
//         bytes memory response = abi.encode(uint256(1));
//         mockRouter.fulfillRequest(address(orderBook), requestId, response, "");
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.PaymentVerified));
        
//         // 4. Complete the order
//         orderBook.mockCompleteOrder(orderId);
//         assertEq(uint8(orderBook.getOrderStatus(orderId)), uint8(OrderBookChainlinkTest.OrderStatus.Completed));
//     }

//     // ============ Error Cases ============
    
//     function test_VerifyPayment_OrderNotFound() public {
//         vm.expectRevert(OrderBookChainlinkTest.OrderNotFound.selector);
//         orderBook.verifyPayment(999, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
//     }

//     function test_VerifyPayment_RequestAlreadyPending() public {
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
        
//         // First request
//         orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
        
//         // Second request should fail
//         vm.expectRevert(OrderBookChainlinkTest.RequestAlreadyPending.selector);
//         orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
//     }

//     function test_MockCompleteOrder_PaymentNotVerified() public {
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
        
//         vm.expectRevert("Payment not verified");
//         orderBook.mockCompleteOrder(orderId);
//     }

//     // ============ Gas Usage Tests ============
    
//     function test_GasUsage_CreateOrder() public {
//         uint256 gasBefore = gasleft();
//         orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
//         uint256 gasUsed = gasBefore - gasleft();
        
//         console.log("Gas used for mockCreateOrder:", gasUsed);
//         assertLt(gasUsed, 100000); // Should be less than 100k gas
//     }

//     function test_GasUsage_VerifyPayment() public {
//         uint256 orderId = orderBook.mockCreateOrder(alice, bob, TEST_AMOUNT_USDC, TEST_PRICE_BOB);
        
//         uint256 gasBefore = gasleft();
//         orderBook.verifyPayment(orderId, TEST_API_URL, TEST_API_KEY, TEST_EXPECTED_AMOUNT, TEST_BUYER_ACCOUNT);
//         uint256 gasUsed = gasBefore - gasleft();
        
//         console.log("Gas used for verifyPayment:", gasUsed);
//         assertLt(gasUsed, 200000); // Should be less than 200k gas
//     }
// }