// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/TratoHechoP2P.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Script to populate TratoHechoP2P contract with sample orders
 * @dev Creates orders for 4 different users with small USDC amounts
 * Example:
 * yarn deploy --file PopulateOrders.s.sol --network sepolia
 */
contract PopulateOrders is ScaffoldETHDeploy {
    // USDC token address on Ethereum Sepolia
    address constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    // Sample user addresses (you can replace these with actual addresses)
    address constant USER_1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Alice
    address constant USER_2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Bob
    address constant USER_3 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Charlie
    address constant USER_4 = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // David

    function run() external ScaffoldEthDeployerRunner {
        // Get the deployed contract address from deployments
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        
        // Read the deployment file to get the contract address
        string memory deploymentData = vm.readFile(path);
        address contractAddress = vm.parseJsonAddress(deploymentData, ".TratoHechoP2P");
        
        TratoHechoP2P p2p = TratoHechoP2P(contractAddress);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        // Create orders for each user
        _createOrderForUser(p2p, usdc, USER_1, 0.1 ether, 14.5 * 10**2); // 0.1 USDC = 14.5 BOB
        _createOrderForUser(p2p, usdc, USER_2, 0.2 ether, 15.0 * 10**2);   // 0.2 USDC = 15.0 BOB
        _createOrderForUser(p2p, usdc, USER_3, 0.3 ether, 14.8 * 10**2); // 0.3 USDC = 14.8 BOB
        _createOrderForUser(p2p, usdc, USER_4, 0.4 ether, 15.2 * 10**2);   // 0.4 USDC = 15.2 BOB
    }
    
    function _createOrderForUser(
        TratoHechoP2P p2p,
        IERC20 usdc,
        address user,
        uint256 usdcAmount,
        uint256 bobPrice
    ) internal {
        // Calculate USDC amount in correct decimals (6 decimals)
        uint256 usdcAmountInDecimals = (usdcAmount * 10**6) / 1 ether;
        
        // Set deadline to 24 hours from now
        uint256 deadline = block.timestamp + 24 hours;
        
        // Switch to user context
        vm.startPrank(user);
        
        // Approve USDC spending
        usdc.approve(address(p2p), usdcAmountInDecimals);
        
        // Create the order
        uint256 orderId = p2p.createSellOrder(usdcAmountInDecimals, bobPrice, deadline);
        
        vm.stopPrank();
    }
}

/**
 * @notice Script to create a single order with custom parameters
 * @dev Allows creating orders with specific amounts and prices
 * Example:
 * yarn deploy --file PopulateOrders.s.sol --sig "createCustomOrder(address,uint256,uint256)" --network sepolia
 */
contract CreateCustomOrder is ScaffoldETHDeploy {
    address constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    function createCustomOrder(
        address seller,
        uint256 usdcAmount, // Amount in USDC (e.g., 100 = 0.1 USDC)
        uint256 bobPrice     // Price in BOB per USDC (e.g., 1450 = 14.50 BOB)
    ) external ScaffoldEthDeployerRunner {
        // Get the deployed contract address
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        
        string memory deploymentData = vm.readFile(path);
        address contractAddress = vm.parseJsonAddress(deploymentData, ".TratoHechoP2P");
        
        TratoHechoP2P p2p = TratoHechoP2P(contractAddress);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        // Convert to correct decimals
        uint256 usdcAmountInDecimals = usdcAmount * 10**6 / 1000; // Convert from millis
        uint256 bobPriceInDecimals = bobPrice * 10**2 / 100; // Convert from centis
        uint256 deadline = block.timestamp + 24 hours;
        
        // Check seller balance
        uint256 currentBalance = usdc.balanceOf(seller);
        require(currentBalance >= usdcAmountInDecimals, "Insufficient USDC balance");
        
        // Switch to seller context
        vm.startPrank(seller);
        
        // Approve USDC spending
        usdc.approve(address(p2p), usdcAmountInDecimals);
        
        // Create the order
        uint256 orderId = p2p.createSellOrder(usdcAmountInDecimals, bobPriceInDecimals, deadline);
        
        vm.stopPrank();
    }
} 