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

contract TratoHechoP2P_CCTP_LocalTest is Test {
    TratoHechoP2P_CCTP public p2p;
    MockUSDC public usdc;

    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant USDC_AMOUNT = 100 * 10**6;
    uint256 constant BOB_PRICE = 1000 * 10**2;
    uint256 constant ORDER_DURATION = 30 minutes;

    function setUp() public {
        usdc = new MockUSDC();
        // Deploy the contract with the mock USDC address
        vm.etch(address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238), address(usdc).code); // Patch the address used in the contract
        p2p = new TratoHechoP2P_CCTP();

        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.mint(alice, 1000 * 10**6);
        usdcAtFixed.mint(bob, 500 * 10**6);
    }

    function testCreateAndCompleteOrderSameChain() public {
        // Alice approves USDC transfer to the contract first
        vm.startPrank(alice);
        MockUSDC usdcAtFixed = MockUSDC(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        usdcAtFixed.approve(address(p2p), USDC_AMOUNT);
        
        // Alice creates an order (USDC is automatically transferred to contract escrow)
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

        // Alice completes the order (no approval needed, USDC already in escrow)
        vm.startPrank(alice);
        p2p.completeOrder(orderId);
        vm.stopPrank();

        // Check balances and order status
        assertEq(usdcAtFixed.balanceOf(alice), 1000 * 10**6 - USDC_AMOUNT);
        assertEq(usdcAtFixed.balanceOf(bob), 500 * 10**6 + USDC_AMOUNT);
        (,,,,,TratoHechoP2P_CCTP.OrderStatus status,,,,) = p2p.orders(orderId);
        assertEq(uint(status), uint(TratoHechoP2P_CCTP.OrderStatus.Completed));
    }
}