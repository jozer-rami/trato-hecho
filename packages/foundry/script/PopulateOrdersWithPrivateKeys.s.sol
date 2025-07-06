// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/TratoHechoP2P.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Script to populate TratoHechoP2P contract with orders using private keys from .env
 * @dev Creates orders for 4 different users with small USDC amounts
 * 
 * Setup:
 * 1. Add these to your .env file:
 *    PRIVATE_KEY_1=0x... (Alice's private key)
 *    PRIVATE_KEY_2=0x... (Bob's private key)
 *    PRIVATE_KEY_3=0x... (Charlie's private key)
 *    PRIVATE_KEY_4=0x... (David's private key)
 * 
 * 2. Update P2P_CONTRACT_ADDRESS below with your deployed contract address
 * 
 * Usage:
 * yarn deploy --file PopulateOrdersWithPrivateKeys.s.sol --network sepolia
 */
contract PopulateOrdersWithPrivateKeys is ScaffoldETHDeploy {
    // USDC token address on Ethereum Sepolia
    address constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    // TODO: Update this with your deployed TratoHechoP2P contract address
    address constant P2P_CONTRACT_ADDRESS = 0xAeC909EC861f572Eb0724714ab21D861E51A1853;
    
    // Order details for each user
    struct OrderDetails {
        string userName;
        uint256 usdcAmount; // in USDC (6 decimals)
        uint256 bobPrice;   // BOB per USDC (18 decimals)
    }
    
    OrderDetails[] public orders;
    
    constructor() {
        // Initialize order details
        orders.push(OrderDetails("Alice", 0.1e6, 14.5e18));   // 0.1 USDC at 14.5 BOB/USDC
        orders.push(OrderDetails("Bob", 0.2e6, 15.0e18));     // 0.2 USDC at 15.0 BOB/USDC
        orders.push(OrderDetails("Charlie", 0.3e6, 14.8e18)); // 0.3 USDC at 14.8 BOB/USDC
        orders.push(OrderDetails("David", 0.4e6, 15.2e18));   // 0.4 USDC at 15.2 BOB/USDC
    }
    
    function run() external {
        require(P2P_CONTRACT_ADDRESS != address(0), "Please update P2P_CONTRACT_ADDRESS");
        
        TratoHechoP2P p2p = TratoHechoP2P(P2P_CONTRACT_ADDRESS);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        console.log("=== Creating Orders with Private Keys ===");
        console.log("P2P Contract:", P2P_CONTRACT_ADDRESS);
        console.log("USDC Token:", USDC_ADDRESS);
        
        // Get private keys from environment variables using vm.envUint()
        uint256[] memory privateKeys = new uint256[](4);
        privateKeys[0] = vm.envUint("PRIVATE_KEY_1");
        privateKeys[1] = vm.envUint("PRIVATE_KEY_2");
        privateKeys[2] = vm.envUint("PRIVATE_KEY_3");
        privateKeys[3] = vm.envUint("PRIVATE_KEY_4");
        
        for (uint256 i = 0; i < orders.length; i++) {
            address userAddress = vm.addr(privateKeys[i]);
            
            console.log("\n--- Creating order for", orders[i].userName, "---");
            console.log("User address:", userAddress);
            
            vm.startBroadcast(privateKeys[i]);
            
            // Check USDC balance
            uint256 balance = usdc.balanceOf(userAddress);
            console.log("USDC Balance:", balance / 10**6, "USDC");
            
            if (balance >= orders[i].usdcAmount) {
                _createOrder(p2p, usdc, orders[i], userAddress);
            } else {
                console.log("[ERROR] Insufficient USDC balance for", orders[i].userName);
                console.log("   Required:", orders[i].usdcAmount / 10**6, "USDC");
                console.log("   Available:", balance / 10**6, "USDC");
            }
            
            vm.stopBroadcast();
        }
        
        console.log("\n=== Orders Creation Completed ===");
    }
    
    function _createOrder(TratoHechoP2P p2p, IERC20 usdc, OrderDetails memory order, address seller) internal {
        // Approve USDC spending
        usdc.approve(address(p2p), order.usdcAmount);
        
        // Calculate BOB amount
        uint256 bobAmount = (order.usdcAmount * order.bobPrice) / 1e18;
        
        // Set deadline to 24 hours from now
        uint256 deadline = block.timestamp + 24 hours;
        
        // Create the order
        uint256 orderId = p2p.createSellOrder(order.usdcAmount, bobAmount, deadline);
        
        console.log("[SUCCESS] Order created for", order.userName);
        console.log("   Order ID:", orderId);
        console.log("   USDC Amount:", order.usdcAmount / 10**6, "USDC");
        console.log("   BOB Price:", order.bobPrice / 1e18, "BOB/USDC");
        console.log("   Total BOB:", bobAmount / 1e18, "BOB");
        console.log("   Seller:", seller);
    }
    
    /**
     * @dev Function to check balances before creating orders
     * Usage: yarn deploy --file PopulateOrdersWithPrivateKeys.s.sol --sig "checkBalances()" --network sepolia
     */
    function checkBalances() external view {
        require(P2P_CONTRACT_ADDRESS != address(0), "Please update P2P_CONTRACT_ADDRESS");
        
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        console.log("=== Checking USDC Balances ===");
        
        // Check balances for all private key accounts
        for (uint256 i = 0; i < 4; i++) {
            try vm.envUint(string(abi.encodePacked("PRIVATE_KEY_", vm.toString(i + 1)))) returns (uint256 pk) {
                address user = vm.addr(pk);
                uint256 balance = usdc.balanceOf(user);
                // console.log("User", i + 1, "(", orders[i].userName, "):", user);
                console.log("  Balance:", balance / 10**6, "USDC");
                console.log("  Required:", orders[i].usdcAmount / 10**6, "USDC");
                console.log("  Status:", balance >= orders[i].usdcAmount ? "[SUFFICIENT]" : "[INSUFFICIENT]");
            } catch {
                console.log("PRIVATE_KEY_", i + 1, "not found in .env");
            }
        }
    }
}