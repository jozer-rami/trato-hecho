// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/TratoHechoP2P.sol";

// Mock USDC contract for testing
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

// Testable version of TratoHechoP2P without Chainlink dependencies
contract TestableTratoHechoP2P {
    using stdStorage for StdStorage;
    
    // Copy all the structs and enums from the main contract
    enum OrderStatus {
        Created,
        Accepted,
        PaymentPending,
        PaymentVerified,
        Completed,
        Cancelled,
        Expired,
        Failed
    }

    struct Order {
        uint256 id;
        address seller;
        address buyer;
        uint256 amountUSDC;
        uint256 priceBOB;
        OrderStatus status;
        uint256 createdAt;
        uint256 deadline;
    }

    struct RequestIdentity {
        uint256 orderId;
        address requester;
        string referenceId;
    }

    // State variables
    mapping(uint256 => Order) public orders;
    mapping(bytes32 => RequestIdentity) public requestToOrder;
    uint256 public nextOrderId = 1;
    address public owner;
    MockUSDC public usdcToken;

    // Events (copy from main contract)
    event OrderCreated(uint256 indexed orderId, address indexed seller, uint256 amountUSDC, uint256 priceBOB, uint256 deadline);
    event OrderAccepted(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event PaymentVerificationRequested(uint256 indexed orderId, bytes32 indexed requestId, address indexed requester);
    event PaymentVerified(uint256 indexed orderId, bool verified, bytes32 indexed requestId);
    event OrderCompleted(uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 amountUSDC);
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

    constructor(address _usdcToken) {
        owner = msg.sender;
        usdcToken = MockUSDC(_usdcToken);
    }

    // Modifiers (copy from main contract)
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

    // Copy main contract functions (without Chainlink dependencies)
    function createSellOrder(uint256 amountUSDC, uint256 priceBOB, uint256 deadline) external returns (uint256 orderId) {
        if (amountUSDC == 0) revert InvalidAmount(amountUSDC);
        if (priceBOB == 0) revert InvalidAmount(priceBOB);
        if (deadline <= block.timestamp) revert InvalidDeadline(deadline);
        
        uint256 sellerBalance = usdcToken.balanceOf(msg.sender);
        if (sellerBalance < amountUSDC) {
            revert InsufficientUSDCBalance(msg.sender, amountUSDC, sellerBalance);
        }

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

    function acceptOrder(uint256 orderId) external validOrder(orderId) inStatus(orderId, OrderStatus.Created) {
        Order storage order = orders[orderId];
        
        if (msg.sender == order.seller) {
            revert UnauthorizedAccess(msg.sender, address(0));
        }

        order.buyer = msg.sender;
        order.status = OrderStatus.Accepted;

        emit OrderAccepted(orderId, msg.sender, order.seller);
    }

    // Mock payment verification for testing
    function mockVerifyPayment(uint256 orderId, bool shouldSucceed) external validOrder(orderId) onlyBuyer(orderId) inStatus(orderId, OrderStatus.Accepted) {
        orders[orderId].status = OrderStatus.PaymentPending;
        
        // Simulate async callback
        bytes32 mockRequestId = keccak256(abi.encodePacked(orderId, block.timestamp));
        
        if (shouldSucceed) {
            orders[orderId].status = OrderStatus.PaymentVerified;
            emit PaymentVerified(orderId, true, mockRequestId);
        } else {
            orders[orderId].status = OrderStatus.Failed;
            emit PaymentVerified(orderId, false, mockRequestId);
        }
    }

    function completeOrder(uint256 orderId) external validOrder(orderId) onlySeller(orderId) inStatus(orderId, OrderStatus.PaymentVerified) {
        Order storage order = orders[orderId];
        order.status = OrderStatus.Completed;

        bool success = usdcToken.transferFrom(order.seller, order.buyer, order.amountUSDC);
        require(success, "USDC transfer failed");

        emit OrderCompleted(orderId, order.seller, order.buyer, order.amountUSDC);
    }

    function cancelOrder(uint256 orderId) external onlySeller(orderId) inStatus(orderId, OrderStatus.Created) {
        orders[orderId].status = OrderStatus.Cancelled;
        emit OrderCancelled(orderId);
    }

    function markExpired(uint256 orderId) external {
        Order storage order = orders[orderId];
        
        if (order.id == 0) revert OrderNotFound(orderId);
        if (order.deadline > block.timestamp) revert OrderAlreadyExpired(orderId);
        if (order.status == OrderStatus.Completed || order.status == OrderStatus.Cancelled) {
            return;
        }

        order.status = OrderStatus.Expired;
        emit OrderExpired(orderId);
    }

    // View functions
    function getAvailableOrders(uint256 limit) external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](limit);

        for (uint256 i = 1; i < nextOrderId && count < limit; i++) {
            Order storage order = orders[i];
            if (order.status == OrderStatus.Created && order.deadline > block.timestamp) {
                tempIds[count] = i;
                count++;
            }
        }

        orderIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = tempIds[i];
        }
    }

    function getOrdersBySeller(address seller, uint256 limit) external view returns (uint256[] memory orderIds) {
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

    function getOrdersByBuyer(address buyer, uint256 limit) external view returns (uint256[] memory orderIds) {
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

    function getOrder(uint256 orderId) external view returns (Order memory order) {
        order = orders[orderId];
    }
}

contract TratoHechoP2PTest is Test {
    TestableTratoHechoP2P public p2p;
    MockUSDC public usdc;
    
    address public alice = address(0x1); // Seller
    address public bob = address(0x2);   // Buyer
    address public charlie = address(0x3); // Another user
    
    uint256 constant USDC_AMOUNT = 100 * 10**6; // 100 USDC (6 decimals)
    uint256 constant BOB_PRICE = 1000 * 10**2;  // 1000 BOB (2 decimals)
    uint256 constant ORDER_DURATION = 30 minutes;

    event OrderCreated(uint256 indexed orderId, address indexed seller, uint256 amountUSDC, uint256 priceBOB, uint256 deadline);
    event OrderAccepted(uint256 indexed orderId, address indexed buyer, address indexed seller);
    event PaymentVerified(uint256 indexed orderId, bool verified, bytes32 indexed requestId);
    event OrderCompleted(uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 amountUSDC);
    event OrderCancelled(uint256 indexed orderId);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Deploy testable P2P contract
        p2p = new TestableTratoHechoP2P(address(usdc));
        
        // Setup initial balances
        usdc.mint(alice, 1000 * 10**6); // 1000 USDC to Alice
        usdc.mint(bob, 500 * 10**6);    // 500 USDC to Bob
        usdc.mint(charlie, 200 * 10**6); // 200 USDC to Charlie
        
        // Setup labels for better test output
        vm.label(alice, "Alice (Seller)");
        vm.label(bob, "Bob (Buyer)");
        vm.label(charlie, "Charlie");
        vm.label(address(p2p), "P2P Contract");
        vm.label(address(usdc), "Mock USDC");
    }

    // ========== ORDER CREATION TESTS ==========

    function testCreateSellOrder() public {
        vm.startPrank(alice);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        
        vm.expectEmit(true, true, false, true);
        emit OrderCreated(1, alice, USDC_AMOUNT, BOB_PRICE, deadline);
        
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        
        // Verify order details
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertEq(order.id, 1);
        assertEq(order.seller, alice);
        assertEq(order.buyer, address(0));
        assertEq(order.amountUSDC, USDC_AMOUNT);
        assertEq(order.priceBOB, BOB_PRICE);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Created);
        assertEq(order.deadline, deadline);
        
        vm.stopPrank();
    }

    function testCreateSellOrderInsufficientBalance() public {
        vm.startPrank(alice);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 tooMuchUSDC = 2000 * 10**6; // More than Alice has
        
        vm.expectRevert(
            abi.encodeWithSelector(
                TestableTratoHechoP2P.InsufficientUSDCBalance.selector,
                alice,
                tooMuchUSDC,
                1000 * 10**6
            )
        );
        
        p2p.createSellOrder(tooMuchUSDC, BOB_PRICE, deadline);
        
        vm.stopPrank();
    }

    function testCreateSellOrderInvalidAmount() public {
        vm.startPrank(alice);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.InvalidAmount.selector, 0));
        p2p.createSellOrder(0, BOB_PRICE, deadline);
        
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.InvalidAmount.selector, 0));
        p2p.createSellOrder(USDC_AMOUNT, 0, deadline);
        
        vm.stopPrank();
    }

    function testCreateSellOrderInvalidDeadline() public {
        vm.startPrank(alice);
        
        uint256 pastDeadline = block.timestamp - 1;
        
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.InvalidDeadline.selector, pastDeadline));
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, pastDeadline);
        
        vm.stopPrank();
    }

    // ========== ORDER ACCEPTANCE TESTS ==========

    function testAcceptOrder() public {
        // Alice creates order
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        // Bob accepts order
        vm.startPrank(bob);
        
        vm.expectEmit(true, true, true, false);
        emit OrderAccepted(orderId, bob, alice);
        
        p2p.acceptOrder(orderId);
        
        // Verify order state
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertEq(order.buyer, bob);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Accepted);
        
        vm.stopPrank();
    }

    function testSellerCannotAcceptOwnOrder() public {
        // Alice creates order
        vm.startPrank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        // Alice tries to accept her own order
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.UnauthorizedAccess.selector, alice, address(0)));
        p2p.acceptOrder(orderId);
        
        vm.stopPrank();
    }

    function testAcceptNonExistentOrder() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.OrderNotFound.selector, 999));
        p2p.acceptOrder(999);
    }

    function testAcceptExpiredOrder() public {
        // Alice creates order with short deadline
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + 1);
        
        // Time passes
        vm.warp(block.timestamp + 2);
        
        // Bob tries to accept expired order
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.OrderAlreadyExpired.selector, orderId));
        p2p.acceptOrder(orderId);
    }

    // ========== PAYMENT VERIFICATION TESTS ==========

    function testMockPaymentVerificationSuccess() public {
        // Setup order
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        // Mock successful payment verification
        vm.startPrank(bob);
        
        vm.expectEmit(true, false, false, false);
        emit PaymentVerified(orderId, true, bytes32(0));
        
        p2p.mockVerifyPayment(orderId, true);
        
        // Verify order status
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.PaymentVerified);
        
        vm.stopPrank();
    }

    function testMockPaymentVerificationFailure() public {
        // Setup order
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        // Mock failed payment verification
        vm.startPrank(bob);
        
        vm.expectEmit(true, false, false, false);
        emit PaymentVerified(orderId, false, bytes32(0));
        
        p2p.mockVerifyPayment(orderId, false);
        
        // Verify order status
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Failed);
        
        vm.stopPrank();
    }

    function testOnlyBuyerCanVerifyPayment() public {
        // Setup order
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        // Charlie tries to verify payment
        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.UnauthorizedAccess.selector, charlie, bob));
        p2p.mockVerifyPayment(orderId, true);
    }

    // ========== ORDER COMPLETION TESTS ==========

    function testCompleteOrder() public {
        // Setup and verify payment
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, true);
        
        // Alice approves USDC transfer
        vm.prank(alice);
        usdc.approve(address(p2p), USDC_AMOUNT);
        
        // Alice completes order
        vm.startPrank(alice);
        
        vm.expectEmit(true, true, true, true);
        emit OrderCompleted(orderId, alice, bob, USDC_AMOUNT);
        
        p2p.completeOrder(orderId);
        
        // Verify balances
        assertEq(usdc.balanceOf(alice), 1000 * 10**6 - USDC_AMOUNT);
        assertEq(usdc.balanceOf(bob), 500 * 10**6 + USDC_AMOUNT);
        
        // Verify order status
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Completed);
        
        vm.stopPrank();
    }

    function testCompleteOrderWithoutApproval() public {
        // Setup and verify payment
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, true);
        
        // Alice tries to complete without approval
        vm.prank(alice);
        vm.expectRevert("USDC transfer failed");
        p2p.completeOrder(orderId);
    }

    function testOnlySellerCanCompleteOrder() public {
        // Setup and verify payment
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, true);
        
        // Bob tries to complete order
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TestableTratoHechoP2P.UnauthorizedAccess.selector, bob, alice));
        p2p.completeOrder(orderId);
    }

    // ========== ORDER CANCELLATION TESTS ==========

    function testCancelOrder() public {
        vm.startPrank(alice);
        
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.expectEmit(true, false, false, false);
        emit OrderCancelled(orderId);
        
        p2p.cancelOrder(orderId);
        
        // Verify order status
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Cancelled);
        
        vm.stopPrank();
    }

    function testCannotCancelAcceptedOrder() public {
        // Setup accepted order
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        // Alice tries to cancel accepted order
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                TestableTratoHechoP2P.InvalidOrderStatus.selector,
                orderId,
                TestableTratoHechoP2P.OrderStatus.Created,
                TestableTratoHechoP2P.OrderStatus.Accepted
            )
        );
        p2p.cancelOrder(orderId);
    }

    // ========== MARKETPLACE VIEW TESTS ==========

    function testGetAvailableOrders() public {
        // Create multiple orders
        vm.startPrank(alice);
        uint256 orderId1 = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        uint256 orderId2 = p2p.createSellOrder(USDC_AMOUNT * 2, BOB_PRICE * 2, block.timestamp + ORDER_DURATION);
        vm.stopPrank();
        
        vm.prank(charlie);
        uint256 orderId3 = p2p.createSellOrder(50 * 10**6, 500 * 10**2, block.timestamp + ORDER_DURATION);
        
        // Accept one order
        vm.prank(bob);
        p2p.acceptOrder(orderId2);
        
        // Get available orders
        uint256[] memory availableOrders = p2p.getAvailableOrders(10);
        
        // Should return orderId1 and orderId3 (not orderId2 since it's accepted)
        assertEq(availableOrders.length, 2);
        assertEq(availableOrders[0], orderId1);
        assertEq(availableOrders[1], orderId3);
    }

    function testGetOrdersBySeller() public {
        // Alice creates orders
        vm.startPrank(alice);
        uint256 orderId1 = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        uint256 orderId2 = p2p.createSellOrder(USDC_AMOUNT * 2, BOB_PRICE * 2, block.timestamp + ORDER_DURATION);
        vm.stopPrank();
        
        // Charlie creates order
        vm.prank(charlie);
        p2p.createSellOrder(50 * 10**6, 500 * 10**2, block.timestamp + ORDER_DURATION);
        
        // Get Alice's orders
        uint256[] memory aliceOrders = p2p.getOrdersBySeller(alice, 10);
        
        assertEq(aliceOrders.length, 2);
        assertEq(aliceOrders[0], orderId1);
        assertEq(aliceOrders[1], orderId2);
        
        // Get Charlie's orders
        uint256[] memory charlieOrders = p2p.getOrdersBySeller(charlie, 10);
        assertEq(charlieOrders.length, 1);
    }

    function testGetOrdersByBuyer() public {
        // Create orders
        vm.prank(alice);
        uint256 orderId1 = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(charlie);
        uint256 orderId2 = p2p.createSellOrder(50 * 10**6, 500 * 10**2, block.timestamp + ORDER_DURATION);
        
        // Bob accepts both orders
        vm.startPrank(bob);
        p2p.acceptOrder(orderId1);
        p2p.acceptOrder(orderId2);
        vm.stopPrank();
        
        // Get Bob's orders
        uint256[] memory bobOrders = p2p.getOrdersByBuyer(bob, 10);
        
        assertEq(bobOrders.length, 2);
        assertEq(bobOrders[0], orderId1);
        assertEq(bobOrders[1], orderId2);
    }

    // ========== EXPIRATION TESTS ==========

    function testMarkExpired() public {
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + 1);
        
        // Time passes
        vm.warp(block.timestamp + 2);
        
        // Anyone can mark as expired
        vm.prank(charlie);
        p2p.markExpired(orderId);
        
        // Verify order status
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Expired);
    }

    // ========== INTEGRATION TESTS ==========

    function testCompleteTradeFlow() public {
        console.log("=== Starting Complete Trade Flow Test ===");
        
        // 1. Alice creates sell order
        console.log("1. Alice creates sell order");
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        console.log("   Order ID:", orderId);
        
        // 2. Bob accepts order
        console.log("2. Bob accepts order");
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        // 3. Bob verifies payment
        console.log("3. Bob verifies payment");
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, true);
        
        // 4. Alice approves USDC transfer
        console.log("4. Alice approves USDC transfer");
        vm.prank(alice);
        usdc.approve(address(p2p), USDC_AMOUNT);
        
        // 5. Alice completes order
        console.log("5. Alice completes order");
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        
        vm.prank(alice);
        p2p.completeOrder(orderId);
        
        // 6. Verify final state
        console.log("6. Verifying final state");
        uint256 aliceBalanceAfter = usdc.balanceOf(alice);
        uint256 bobBalanceAfter = usdc.balanceOf(bob);
        
        console.log("   Alice USDC before:", aliceBalanceBefore / 10**6);
        console.log("   Alice USDC after:", aliceBalanceAfter / 10**6);
        console.log("   Bob USDC before:", bobBalanceBefore / 10**6);
        console.log("   Bob USDC after:", bobBalanceAfter / 10**6);
        
        assertEq(aliceBalanceAfter, aliceBalanceBefore - USDC_AMOUNT);
        assertEq(bobBalanceAfter, bobBalanceBefore + USDC_AMOUNT);
        
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Completed);
        
        console.log("=== Trade Flow Test Completed Successfully ===");
    }

    function testMultipleOrdersScenario() public {
        console.log("=== Testing Multiple Orders Scenario ===");
        
        // Alice creates multiple orders
        vm.startPrank(alice);
        uint256 order1 = p2p.createSellOrder(100 * 10**6, 1000 * 10**2, block.timestamp + ORDER_DURATION);
        uint256 order2 = p2p.createSellOrder(200 * 10**6, 2200 * 10**2, block.timestamp + ORDER_DURATION);
        uint256 order3 = p2p.createSellOrder(50 * 10**6, 550 * 10**2, block.timestamp + ORDER_DURATION);
        vm.stopPrank();
        
        // Charlie creates an order
        vm.prank(charlie);
        uint256 order4 = p2p.createSellOrder(75 * 10**6, 825 * 10**2, block.timestamp + ORDER_DURATION);
        
        // Bob accepts order1 and order4
        vm.startPrank(bob);
        p2p.acceptOrder(order1);
        p2p.acceptOrder(order4);
        vm.stopPrank();
        
        // Verify marketplace state
        uint256[] memory availableOrders = p2p.getAvailableOrders(10);
        assertEq(availableOrders.length, 2); // order2 and order3
        
        uint256[] memory aliceOrders = p2p.getOrdersBySeller(alice, 10);
        assertEq(aliceOrders.length, 3);
        
        uint256[] memory bobOrders = p2p.getOrdersByBuyer(bob, 10);
        assertEq(bobOrders.length, 2);
        
        console.log("Multiple orders scenario working correctly");
    }

    function testFailureRecoveryScenario() public {
        console.log("=== Testing Failure Recovery Scenario ===");
        
        // 1. Alice creates order
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        // 2. Bob accepts order
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        // 3. Payment verification fails
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, false);
        
        // 4. Verify order is marked as failed
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertTrue(order.status == TestableTratoHechoP2P.OrderStatus.Failed);
        
        // 5. Alice creates a new order (old one is failed)
        vm.prank(alice);
        uint256 newOrderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        // 6. Verify new order is available
        uint256[] memory availableOrders = p2p.getAvailableOrders(10);
        assertEq(availableOrders.length, 1);
        assertEq(availableOrders[0], newOrderId);
        
        console.log("Failure recovery scenario working correctly");
    }

    // ========== EDGE CASE TESTS ==========

    function testMaximumAmounts() public {
        // Test with very large amounts
        uint256 maxUSDC = type(uint256).max / 2;
        uint256 maxBOB = type(uint256).max / 2;
        
        // Mint enough tokens
        usdc.mint(alice, maxUSDC);
        
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(maxUSDC, maxBOB, block.timestamp + ORDER_DURATION);
        
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertEq(order.amountUSDC, maxUSDC);
        assertEq(order.priceBOB, maxBOB);
    }

    function testMinimumAmounts() public {
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(1, 1, block.timestamp + ORDER_DURATION);
        
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertEq(order.amountUSDC, 1);
        assertEq(order.priceBOB, 1);
    }

    function testOrderIdSequence() public {
        // Test that order IDs are sequential
        vm.startPrank(alice);
        
        uint256 orderId1 = p2p.createSellOrder(100 * 10**6, 1000 * 10**2, block.timestamp + ORDER_DURATION);
        uint256 orderId2 = p2p.createSellOrder(200 * 10**6, 2000 * 10**2, block.timestamp + ORDER_DURATION);
        uint256 orderId3 = p2p.createSellOrder(300 * 10**6, 3000 * 10**2, block.timestamp + ORDER_DURATION);
        
        assertEq(orderId1, 1);
        assertEq(orderId2, 2);
        assertEq(orderId3, 3);
        
        vm.stopPrank();
    }

    function testTimestampAccuracy() public {
        uint256 beforeTime = block.timestamp;
        
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        assertGe(order.createdAt, beforeTime);
        assertLe(order.createdAt, block.timestamp);
    }

    // ========== GAS OPTIMIZATION TESTS ==========

    function testGasUsageOrderCreation() public {
        vm.prank(alice);
        
        uint256 gasBefore = gasleft();
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for order creation:", gasUsed);
        // Ensure gas usage is reasonable (adjust threshold as needed)
        assertLt(gasUsed, 200000);
    }

    function testGasUsageOrderAcceptance() public {
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        uint256 gasBefore = gasleft();
        p2p.acceptOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for order acceptance:", gasUsed);
        assertLt(gasUsed, 100000);
    }

    function testGasUsageOrderCompletion() public {
        // Setup completed verification
        vm.prank(alice);
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
        
        vm.prank(bob);
        p2p.acceptOrder(orderId);
        
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, true);
        
        vm.prank(alice);
        usdc.approve(address(p2p), USDC_AMOUNT);
        
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        p2p.completeOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for order completion:", gasUsed);
        assertLt(gasUsed, 150000);
    }

    // ========== STRESS TESTS ==========

    function testManyOrdersPerformance() public {
        console.log("=== Testing Performance with Many Orders ===");
        
        uint256 numOrders = 50;
        
        // Create many orders
        vm.startPrank(alice);
        for (uint256 i = 0; i < numOrders; i++) {
            p2p.createSellOrder(
                (i + 1) * 10**6, 
                (i + 1) * 10**2 * 10, 
                block.timestamp + ORDER_DURATION
            );
        }
        vm.stopPrank();
        
        // Test querying available orders
        uint256 gasBefore = gasleft();
        uint256[] memory availableOrders = p2p.getAvailableOrders(100);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Orders created:", numOrders);
        console.log("Orders retrieved:", availableOrders.length);
        console.log("Gas used for query:", gasUsed);
        
        assertEq(availableOrders.length, numOrders);
    }

    // ========== HELPER FUNCTIONS ==========

    function createSampleOrder() internal returns (uint256 orderId) {
        vm.prank(alice);
        orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, block.timestamp + ORDER_DURATION);
    }

    function acceptSampleOrder(uint256 orderId) internal {
        vm.prank(bob);
        p2p.acceptOrder(orderId);
    }

    function verifySamplePayment(uint256 orderId, bool shouldSucceed) internal {
        vm.prank(bob);
        p2p.mockVerifyPayment(orderId, shouldSucceed);
    }

    function completeSampleOrder(uint256 orderId) internal {
        vm.prank(alice);
        usdc.approve(address(p2p), USDC_AMOUNT);
        
        vm.prank(alice);
        p2p.completeOrder(orderId);
    }

    function printOrderState(uint256 orderId) internal view {
        TestableTratoHechoP2P.Order memory order = p2p.getOrder(orderId);
        console.log("Order", orderId, "state:");
        console.log("  Seller:", order.seller);
        console.log("  Buyer:", order.buyer);
        console.log("  Amount USDC:", order.amountUSDC / 10**6);
        console.log("  Price BOB:", order.priceBOB / 10**2);
        console.log("  Status:", uint256(order.status));
        console.log("  Created:", order.createdAt);
        console.log("  Deadline:", order.deadline);
    }
}