// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/TratoHechoP2P.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Script to approve USDC spending for TratoHechoP2P contract using private keys from .env
 * @dev Approves 100 USDC per wallet for the 4 accounts
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
 * yarn deploy --file ApproveUSDCWithPrivateKeys.s.sol --network sepolia
 */
contract ApproveUSDCWithPrivateKeys is ScaffoldETHDeploy {
    // USDC token address on Ethereum Sepolia
    address constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    // TODO: Update this with your deployed TratoHechoP2P contract address
    address constant P2P_CONTRACT_ADDRESS = 0xAeC909EC861f572Eb0724714ab21D861E51A1853;
    
    // Amount to approve per wallet (100 USDC with 6 decimals)
    uint256 constant APPROVAL_AMOUNT = 100e6;
    
    // User names for logging
    string[] public userNames = ["Alice", "Bob", "Charlie", "David"];
    
    function run() external {
        require(P2P_CONTRACT_ADDRESS != address(0), "Please update P2P_CONTRACT_ADDRESS");
        
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        console.log("=== Approving USDC Spending ===");
        console.log("P2P Contract:", P2P_CONTRACT_ADDRESS);
        console.log("USDC Token:", USDC_ADDRESS);
        console.log("Approval Amount per wallet:", APPROVAL_AMOUNT / 10**6, "USDC");
        
        // Get private keys from environment variables using vm.envUint()
        uint256[] memory privateKeys = new uint256[](4);
        privateKeys[0] = vm.envUint("PRIVATE_KEY_1");
        privateKeys[1] = vm.envUint("PRIVATE_KEY_2");
        privateKeys[2] = vm.envUint("PRIVATE_KEY_3");
        privateKeys[3] = vm.envUint("PRIVATE_KEY_4");
        
        for (uint256 i = 0; i < privateKeys.length; i++) {
            address userAddress = vm.addr(privateKeys[i]);
            
            console.log("\n--- Approving USDC for", userNames[i], "---");
            console.log("User address:", userAddress);
            
            vm.startBroadcast(privateKeys[i]);
            
            // Check current USDC balance
            uint256 balance = usdc.balanceOf(userAddress);
            console.log("USDC Balance:", balance / 10**6, "USDC");
            
            // Check current allowance
            uint256 currentAllowance = usdc.allowance(userAddress, P2P_CONTRACT_ADDRESS);
            console.log("Current Allowance:", currentAllowance / 10**6, "USDC");
            
            if (currentAllowance >= APPROVAL_AMOUNT) {
                console.log("[SKIP] Already approved sufficient amount");
            } else {
                // Approve USDC spending
                usdc.approve(P2P_CONTRACT_ADDRESS, APPROVAL_AMOUNT);
                
                // Verify the approval
                uint256 newAllowance = usdc.allowance(userAddress, P2P_CONTRACT_ADDRESS);
                console.log("[SUCCESS] USDC approved for", userNames[i]);
                console.log("   New Allowance:", newAllowance / 10**6, "USDC");
            }
            
            vm.stopBroadcast();
        }
        
        console.log("\n=== USDC Approval Completed ===");
    }
    
    /**
     * @dev Function to check current allowances
     * Usage: yarn deploy --file ApproveUSDCWithPrivateKeys.s.sol --sig "checkAllowances()" --network sepolia
     */
    function checkAllowances() external view {
        require(P2P_CONTRACT_ADDRESS != address(0), "Please update P2P_CONTRACT_ADDRESS");
        
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        console.log("=== Checking USDC Allowances ===");
        console.log("P2P Contract:", P2P_CONTRACT_ADDRESS);
        console.log("Required Approval:", APPROVAL_AMOUNT / 10**6, "USDC");
        
        // Check allowances for all private key accounts
        for (uint256 i = 0; i < 4; i++) {
            try vm.envUint(string(abi.encodePacked("PRIVATE_KEY_", vm.toString(i + 1)))) returns (uint256 pk) {
                address user = vm.addr(pk);
                uint256 balance = usdc.balanceOf(user);
                uint256 allowance = usdc.allowance(user, P2P_CONTRACT_ADDRESS);
                
                console.log(string.concat("\n", userNames[i], " (", vm.toString(user), "):"));
                console.log("  Balance:", balance / 10**6, "USDC");
                console.log("  Allowance:", allowance / 10**6, "USDC");
                console.log("  Status:", allowance >= APPROVAL_AMOUNT ? "[APPROVED]" : "[NEEDS APPROVAL]");
            } catch {
                console.log("PRIVATE_KEY_", i + 1, "not found in .env");
            }
        }
    }
} 