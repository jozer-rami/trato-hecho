// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../contracts/TratoHechoP2P_CCTP.sol";

// Minimal mock USDC for local testing
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Mock CCTP TokenMessenger for testing
contract MockTokenMessenger {
    uint64 public nonceCounter = 1;
    
    event DepositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        uint64 nonce
    );
    
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external returns (uint64 nonce) {
        nonce = nonceCounter++;
        
        emit DepositForBurn(
            amount,
            destinationDomain,
            mintRecipient,
            burnToken,
            destinationCaller,
            maxFee,
            minFinalityThreshold,
            nonce
        );
        
        return nonce;
    }
}

contract TratoHechoP2P_CCTP_LocalTest is Test {
    TratoHechoP2P_CCTP public p2p;
    MockUSDC public usdc;
    MockTokenMessenger public tokenMessenger;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint256 constant USDC_AMOUNT = 100 * 10**6;
    uint256 constant BOB_PRICE = 1000 * 10**2;
    uint256 constant ORDER_DURATION = 30 minutes;

    function setUp() public {
        usdc = new MockUSDC();
        tokenMessenger = new MockTokenMessenger();
        
        // Patch the USDC address used in the contract
        vm.etch(address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238), address(usdc).code);
        
        // Patch the TokenMessenger address
        vm.etch(address(0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA), address(tokenMessenger).code);
        
        p2p = new TratoHechoP2P_CCTP();

        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.mint(alice, 1000 * 10**6);
        usdcAtFixed.mint(bob, 500 * 10**6);
        usdcAtFixed.mint(charlie, 200 * 10**6);
        

    }

    // ========== SAME-CHAIN TESTS ==========

    function testCreateAndCompleteOrderSameChain() public {
        // Alice approves USDC transfer to the contract first
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        // Alice creates an order
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Bob accepts the order (same-chain)
        vm.startPrank(bob);
        p2p.acceptOrderSameChain(orderId);
        vm.stopPrank();

        // Simulate payment verification (manually set status)
        vm.prank(bob);
        p2p.setOrderStatus(orderId, TratoHechoP2P_CCTP.OrderStatus.PaymentVerified);

        // Alice completes the order
        vm.startPrank(alice);
        p2p.completeOrder(orderId);
        vm.stopPrank();

        // Check balances and order status
        assertEq(usdcAtFixed.balanceOf(alice), 1000 * 10**6 - USDC_AMOUNT);
        assertEq(usdcAtFixed.balanceOf(bob), 500 * 10**6 + USDC_AMOUNT);
        
        TratoHechoP2P_CCTP.Order memory order = p2p.getOrder(orderId);
        assertEq(uint(order.status), uint(TratoHechoP2P_CCTP.OrderStatus.Completed));
        assertEq(order.isCrossChain, false);
        assertEq(order.destinationDomain, 0);
    }

    // ========== CROSS-CHAIN TESTS ==========

    function testCreateAndCompleteOrderCrossChain() public {
        // Mock the CCTP depositForBurn call to return nonce 1
        bytes4 selector = 0x3d4c26e9;
        vm.mockCall(
            address(0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA),
            abi.encodeWithSelector(selector),
            abi.encode(uint64(1))
        );
        
        // Alice approves USDC transfer to the contract first
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        // Alice creates an order
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Bob accepts the order (cross-chain to Avalanche Fuji)
        vm.startPrank(bob);
        p2p.acceptOrder(orderId, 1); // AVAX_FUJI_DOMAIN = 1
        vm.stopPrank();

        // Simulate payment verification
        vm.prank(bob);
        p2p.setOrderStatus(orderId, TratoHechoP2P_CCTP.OrderStatus.PaymentVerified);

        // Alice completes the order (should trigger CCTP)
        vm.startPrank(alice);
        p2p.completeOrder(orderId);
        vm.stopPrank();

        // Check order status and cross-chain transfer details
        TratoHechoP2P_CCTP.Order memory order = p2p.getOrder(orderId);
        assertEq(uint(order.status), uint(TratoHechoP2P_CCTP.OrderStatus.Completed));
        assertEq(order.isCrossChain, true);
        assertEq(order.destinationDomain, 1);

        // Check cross-chain transfer details
        TratoHechoP2P_CCTP.CrossChainTransfer memory transfer = p2p.getCrossChainTransfer(orderId);
        assertEq(transfer.orderId, orderId);
        assertEq(transfer.destinationDomain, 1);
        assertEq(transfer.destinationRecipient, p2p.addressToBytes32Public(bob));
        assertEq(transfer.isPending, true);
        assertEq(transfer.cctpNonce, 1); // Should be the first call
    }

    function testCrossChainOrderWithDifferentDomains() public {
        // Test different destination domains
        uint32[] memory domains = new uint32[](4);
        domains[0] = 1;  // AVAX_FUJI_DOMAIN
        domains[1] = 3;  // ARB_SEPOLIA_DOMAIN
        domains[2] = 6;  // BASE_SEPOLIA_DOMAIN
        domains[3] = 7;  // MATIC_AMOY_DOMAIN

        for (uint i = 0; i < domains.length; i++) {
            // Alice approves USDC transfer for each order
            vm.startPrank(alice);
            MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
            usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
            
            uint256 deadline = block.timestamp + ORDER_DURATION;
            uint256 newOrderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
            vm.stopPrank();

            // Accept with specific domain
            vm.startPrank(bob);
            p2p.acceptOrder(newOrderId, domains[i]);
            vm.stopPrank();

            // Verify order details
            TratoHechoP2P_CCTP.Order memory order = p2p.getOrder(newOrderId);
            assertEq(order.destinationDomain, domains[i]);
            assertEq(order.isCrossChain, true);
        }
    }

    function testInvalidDestinationDomain() public {
        // Alice creates order
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Try to accept with invalid domain
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(TratoHechoP2P_CCTP.InvalidDestinationDomain.selector, 999));
        p2p.acceptOrder(orderId, 999); // Invalid domain
        vm.stopPrank();
    }

    // ========== HELPER FUNCTION TESTS ==========

    function testAddressToBytes32Conversion() public {
        address testAddr = address(0x1234567890123456789012345678901234567890);
        bytes32 converted = p2p.addressToBytes32Public(testAddr);
        assertEq(converted, bytes32(uint256(uint160(testAddr))));
    }

    function testGetSupportedDomains() public {
        (uint32[] memory domains, string[] memory names) = p2p.getSupportedDomains();
        
        assertEq(domains.length, 4);
        assertEq(names.length, 4);
        
        assertEq(domains[0], 1); // AVAX_FUJI_DOMAIN
        assertEq(names[0], "Avalanche Fuji");
        
        assertEq(domains[1], 3); // ARB_SEPOLIA_DOMAIN
        assertEq(names[1], "Arbitrum Sepolia");
        
        assertEq(domains[2], 6); // BASE_SEPOLIA_DOMAIN
        assertEq(names[2], "Base Sepolia");
        
        assertEq(domains[3], 7); // MATIC_AMOY_DOMAIN
        assertEq(names[3], "Polygon Amoy");
    }

    // ========== CCTP INTERFACE TESTS ==========

    function testCCTPDepositForBurnCall() public {
        // Mock the CCTP depositForBurn call to return nonce 1
        // Function selector for depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)
        bytes4 selector = 0x3d4c26e9;
        vm.mockCall(
            address(0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA),
            abi.encodeWithSelector(selector),
            abi.encode(uint64(1))
        );
        
        // Setup order for cross-chain
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        vm.startPrank(bob);
        p2p.acceptOrder(orderId, 1); // AVAX_FUJI_DOMAIN
        vm.stopPrank();

        vm.prank(bob);
        p2p.setOrderStatus(orderId, TratoHechoP2P_CCTP.OrderStatus.PaymentVerified);

        // Complete the order (should trigger CCTP)
        vm.prank(alice);
        p2p.completeOrder(orderId);
        
        // Verify the cross-chain transfer was initiated
        TratoHechoP2P_CCTP.CrossChainTransfer memory transfer = p2p.getCrossChainTransfer(orderId);
        assertEq(transfer.cctpNonce, 1); // Should have called depositForBurn
        
        // Verify the order is marked as cross-chain
        TratoHechoP2P_CCTP.Order memory order = p2p.getOrder(orderId);
        assertEq(order.isCrossChain, true);
        assertEq(order.destinationDomain, 1);
    }

    // ========== ORDER STATUS TESTS ==========

    function testOrderStatusTransitions() public {
        // Create order
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Check initial status
        TratoHechoP2P_CCTP.Order memory order = p2p.getOrder(orderId);
        assertEq(uint(order.status), uint(TratoHechoP2P_CCTP.OrderStatus.Created));

        // Accept order
        vm.prank(bob);
        p2p.acceptOrderSameChain(orderId);
        
        order = p2p.getOrder(orderId);
        assertEq(uint(order.status), uint(TratoHechoP2P_CCTP.OrderStatus.Accepted));

        // Set to payment verified
        vm.prank(bob);
        p2p.setOrderStatus(orderId, TratoHechoP2P_CCTP.OrderStatus.PaymentVerified);
        
        order = p2p.getOrder(orderId);
        assertEq(uint(order.status), uint(TratoHechoP2P_CCTP.OrderStatus.PaymentVerified));

        // Complete order
        vm.prank(alice);
        p2p.completeOrder(orderId);
        
        order = p2p.getOrder(orderId);
        assertEq(uint(order.status), uint(TratoHechoP2P_CCTP.OrderStatus.Completed));
    }

    // ========== ERROR HANDLING TESTS ==========

    function testInsufficientUSDCAllowance() public {
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        
        // Don't approve enough allowance
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT / 2);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                TratoHechoP2P_CCTP.InsufficientUSDCAllowance.selector,
                alice,
                USDC_AMOUNT,
                USDC_AMOUNT / 2
            )
        );
        
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();
    }

    function testUnauthorizedAccess() public {
        // Alice creates order
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        uint256 orderId = p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Charlie tries to accept Alice's order (should work)
        vm.prank(charlie);
        p2p.acceptOrderSameChain(orderId);

        // Alice tries to complete order without payment verification (should fail)
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                TratoHechoP2P_CCTP.InvalidOrderStatus.selector,
                orderId,
                TratoHechoP2P_CCTP.OrderStatus.PaymentVerified,
                TratoHechoP2P_CCTP.OrderStatus.Accepted
            )
        );
        p2p.completeOrder(orderId);
        vm.stopPrank();
    }

    // ========== VIEW FUNCTION TESTS ==========

    function testGetAvailableOrders() public {
        // Create multiple orders
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT * 3);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Get available orders
        uint256[] memory availableOrders = p2p.getAvailableOrders(10);
        assertEq(availableOrders.length, 3);
        assertEq(availableOrders[0], 1);
        assertEq(availableOrders[1], 2);
        assertEq(availableOrders[2], 3);
    }

    function testGetOrdersBySeller() public {
        // Alice creates orders
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT * 2);
        
        uint256 deadline = block.timestamp + ORDER_DURATION;
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Bob creates an order
        vm.startPrank(bob);
        MockUSDC usdcAtFixed2 = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed2.approve(address(p2p), USDC_AMOUNT);
        p2p.createSellOrder(USDC_AMOUNT, BOB_PRICE, deadline);
        vm.stopPrank();

        // Get Alice's orders
        uint256[] memory aliceOrders = p2p.getOrdersBySeller(alice, 10);
        assertEq(aliceOrders.length, 2);
        assertEq(aliceOrders[0], 1);
        assertEq(aliceOrders[1], 2);

        // Get Bob's orders
        uint256[] memory bobOrders = p2p.getOrdersBySeller(bob, 10);
        assertEq(bobOrders.length, 1);
        assertEq(bobOrders[0], 3);
    }
}