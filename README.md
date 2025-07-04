# 🏗 Scaffold-ETH 2

<h4 align="center">
  <a href="https://docs.scaffoldeth.io">Documentation</a> |
  <a href="https://scaffoldeth.io">Website</a>
</h4>

🧪 An open-source, up-to-date toolkit for building decentralized applications (dapps) on the Ethereum blockchain. It's designed to make it easier for developers to create and deploy smart contracts and build user interfaces that interact with those contracts.

⚙️ Built using NextJS, RainbowKit, Foundry, Wagmi, Viem, and Typescript.

- ✅ **Contract Hot Reload**: Your frontend auto-adapts to your smart contract as you edit it.
- 🪝 **[Custom hooks](https://docs.scaffoldeth.io/hooks/)**: Collection of React hooks wrapper around [wagmi](https://wagmi.sh/) to simplify interactions with smart contracts with typescript autocompletion.
- 🧱 [**Components**](https://docs.scaffoldeth.io/components/): Collection of common web3 components to quickly build your frontend.
- 🔥 **Burner Wallet & Local Faucet**: Quickly test your application with a burner wallet and local faucet.
- 🔐 **Integration with Wallet Providers**: Connect to different wallet providers and interact with the Ethereum network.

![Debug Contracts tab](https://github.com/scaffold-eth/scaffold-eth-2/assets/55535804/b237af0c-5027-4849-a5c1-2e31495cccb1)

## Requirements

Before you begin, you need to install the following tools:

- [Node (>= v20.18.3)](https://nodejs.org/en/download/)
- Yarn ([v1](https://classic.yarnpkg.com/en/docs/install/) or [v2+](https://yarnpkg.com/getting-started/install))
- [Git](https://git-scm.com/downloads)

## Quickstart

To get started with Scaffold-ETH 2, follow the steps below:

1. Install dependencies if it was skipped in CLI:

```
cd my-dapp-example
yarn install
```

2. Run a local network in the first terminal:

```
yarn chain
```

This command starts a local Ethereum network using Foundry. The network runs on your local machine and can be used for testing and development. You can customize the network configuration in `packages/foundry/foundry.toml`.

3. On a second terminal, deploy the test contract:

```
yarn deploy
```

This command deploys a test smart contract to the local network. The contract is located in `packages/foundry/contracts` and can be modified to suit your needs. The `yarn deploy` command uses the deploy script located in `packages/foundry/script` to deploy the contract to the network. You can also customize the deploy script.

4. On a third terminal, start your NextJS app:

```
yarn start
```

Visit your app on: `http://localhost:3000`. You can interact with your smart contract using the `Debug Contracts` page. You can tweak the app config in `packages/nextjs/scaffold.config.ts`.

Run smart contract test with `yarn foundry:test`

- Edit your smart contracts in `packages/foundry/contracts`
- Edit your frontend homepage at `packages/nextjs/app/page.tsx`. For guidance on [routing](https://nextjs.org/docs/app/building-your-application/routing/defining-routes) and configuring [pages/layouts](https://nextjs.org/docs/app/building-your-application/routing/pages-and-layouts) checkout the Next.js documentation.
- Edit your deployment scripts in `packages/foundry/script`


## Documentation

Visit our [docs](https://docs.scaffoldeth.io) to learn how to start building with Scaffold-ETH 2.

To know more about its features, check out our [website](https://scaffoldeth.io).

## Contributing to Scaffold-ETH 2

We welcome contributions to Scaffold-ETH 2!

Please see [CONTRIBUTING.MD](https://github.com/scaffold-eth/scaffold-eth-2/blob/main/CONTRIBUTING.md) for more information and guidelines for contributing to Scaffold-ETH 2.


# trato-hecho
Trustless p2p platform

# First idea flow

Detailed User Flow: Bob Buying USDC from Alice
Let me walk you through the complete user journey for Bob, who has fiat currency and wants to purchase USDC from Alice's existing order.
🎯 Initial Setup
Alice (Seller):

Has 100 USDC in her smart wallet
Created an order: "Sell 100 USDC for 500 BOB (Boliviano)"
Already signed EIP-7702 authorization allowing the OrderBook contract to transfer her USDC only if payment is verified

Bob (Buyer):

Has 500 BOB in his bank account
Wants to buy 100 USDC
Has a Web3 wallet (MetaMask) connected to the dApp


📱 Step-by-Step User Flow
Step 1: Bob Discovers the Order
Bob opens the P2P Exchange dApp
↓
Connects his MetaMask wallet
↓
Views available orders on the marketplace
↓
Sees Alice's order: "100 USDC for 500 BOB"
↓
Clicks "View Details" to see:
- Exchange rate: 5 BOB per USDC
- Alice's reputation/history
- Order expiration time
- Payment instructions
Frontend Code Example:

```
javascript// Bob sees this order in the UI
const order = {
  id: 42,
  seller: "0xAlice...",
  amountUSDC: "100.000000", // 100 USDC (6 decimals)
  priceBOB: "500.0", // 500 BOB
  status: "Created",
  deadline: "2025-07-05T12:00:00Z"
};
```
Step 2: Bob Accepts the Order
Bob clicks "Accept Order"
↓
Frontend shows confirmation modal:
- "You will pay: 500 BOB"
- "You will receive: 100 USDC"
- "To wallet: 0xBob..."
↓
Bob confirms the acceptance
↓
Transaction is sent to OrderBook contract
Smart Contract Interaction:
```
solidity// OrderBook.acceptOrder() is called
function acceptOrder(uint256 orderId) external {
    Order storage order = orders[orderId];
    
    // Validation checks
    require(order.status == OrderStatus.Created);
    require(block.timestamp <= order.deadline);
    
    // Update order
    order.buyer = msg.sender; // Bob's address
    order.status = OrderStatus.Accepted;
    
    // Update UserOperation with Bob's address as recipient
    order.userOp.callData = abi.encodeWithSelector(
        IERC20.transfer.selector,
        msg.sender, // Bob will receive the USDC
        order.amountUSDC
    );
    
    emit OrderAccepted(orderId, msg.sender);
}
```

Step 3: Bob Gets Payment Instructions
Order acceptance confirmed ✅
↓
Frontend automatically shows payment details:
- "Send exactly 500 BOB to Alice"
- Bank account details for Alice
- Payment reference: "P2P-ORDER-42"
- Important: "Include this reference in your transfer"
↓
Timer starts: "Complete payment within 30 minutes"
UI Display:
```
javascript// Bob sees this payment screen
const paymentInstructions = {
  amount: "500.00 BOB",
  recipient: "Alice Rodriguez",
  bankAccount: "BANCO-123-456789",
  reference: "P2P-ORDER-42",
  deadline: "30 minutes remaining"
};
```
Step 4: Bob Makes the Bank Transfer
Bob opens his banking app
↓
Creates a new transfer:
- Recipient: Alice Rodriguez
- Account: BANCO-123-456789
- Amount: 500.00 BOB
- Reference: "P2P-ORDER-42" ⚠️ (Critical!)
↓
Confirms and sends the transfer
↓
Returns to P2P dApp
↓
Clicks "I have completed the payment"
Backend Process:
```
javascript// When Bob clicks "Payment completed"
const bankTransfer = {
  fromAccount: "bob-bank-123",
  toAccount: "alice-bank-456", 
  amount: 500.00,
  reference: "P2P-ORDER-42",
  timestamp: "2025-07-04T10:30:00Z",
  status: "processing" // Bank is processing
};
```
Step 5: Automatic Payment Verification
OrderBook contract detects "payment completed" signal
↓
Triggers Chainlink Functions to verify payment
↓
Chainlink calls Banking API with:
- Order ID: 42
- Expected amount: 500 BOB  
- Expected reference: "P2P-ORDER-42"
- Alice's account details
↓
Banking API responds: "Payment confirmed ✅"
Chainlink Functions Code:
```
javascript// This runs off-chain via Chainlink
const orderId = args[0]; // "42"
const expectedAmount = args[1]; // "500"
const reference = args[2]; // "P2P-ORDER-42"

const apiResponse = await Functions.makeHttpRequest({
  url: `${bankingApiUrl}/api/v1/transfers/verify`,
  method: "POST",
  headers: { "Authorization": `Bearer ${apiKey}` },
  data: {
    orderId: orderId,
    expectedAmount: expectedAmount,
    reference: reference,
    recipientAccount: "alice-bank-456"
  }
});

// Banking API confirms payment exists
if (apiResponse.data.confirmed === true) {
  return Functions.encodeUint256(1); // Verified!
} else {
  return Functions.encodeUint256(0); // Not found
}
```
Step 6: Smart Contract Executes the Trade
Chainlink Functions returns "1" (verified)
↓
OrderBook.fulfillRequest() is called automatically
↓
Contract triggers UserOperation execution:
- Uses Alice's pre-signed EIP-7702 authorization
- Transfers 100 USDC from Alice's smart wallet to Bob
- No gas fees for Alice (gasless transaction)
↓
Trade completed! 🎉
Smart Contract Execution:
```
solidityfunction fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
    uint256 orderId = requestIdToOrderId[requestId];
    Order storage order = orders[orderId];
    
    uint256 result = abi.decode(response, (uint256));
    
    if (result == 1) { // Payment verified
        order.status = OrderStatus.PaymentVerified;
        _executeOrder(orderId); // Execute the USDC transfer
    }
}

function _executeOrder(uint256 orderId) internal {
    Order storage order = orders[orderId];
    
    // Submit Alice's pre-signed UserOperation to EntryPoint
    UserOperation[] memory ops = new UserOperation[](1);
    ops[0] = order.userOp; // Contains Alice's signature
    
    // EntryPoint executes: Alice's wallet → transfer 100 USDC → Bob
    ENTRY_POINT.handleOps(ops, payable(address(this)));
    
    order.status = OrderStatus.Completed;
    emit OrderCompleted(orderId, order.seller, order.buyer, order.amountUSDC);
}
```
Step 7: Bob Receives Confirmation
Bob's wallet balance updates: +100 USDC ✅
↓
Frontend shows success message:
- "Trade completed successfully!"
- "You received: 100 USDC"
- "Transaction hash: 0x..."
- "Rate your experience with Alice"
↓
Bob can now use his 100 USDC for other purposes
Final State:
```
javascript// Order final state
const completedOrder = {
  id: 42,
  seller: "0xAlice...",
  buyer: "0xBob...",
  amountUSDC: "100.000000",
  priceBOB: "500.0",
  status: "Completed", // ✅
  completedAt: "2025-07-04T10:35:00Z"
};

// Bob's wallet
bobWallet.balance.USDC += 100; // ✅ Bob received USDC

// Alice's bank account  
aliceBank.balance.BOB += 500; // ✅ Alice received fiat
```

🔐 Security & Trust Mechanisms
For Bob (Buyer Protection):

Escrow-like Security: Alice's USDC is "locked" via smart contract - she can't spend it elsewhere
Atomic Settlement: USDC is only transferred if and only if payment is verified
No Prepayment: Bob pays fiat directly to Alice's bank account (no intermediary)
Transparency: All steps are visible on blockchain

For Alice (Seller Protection):

Payment Verification: Chainlink Functions confirms bank transfer before releasing USDC
Non-Custodial: Her USDC never leaves her control until payment is confirmed
Gasless: She doesn't pay gas fees for the final transfer (EIP-7702 magic)
Reference Matching: System verifies correct payment reference

Trust Requirements:

Banking API: Must accurately report payment status
Chainlink Functions: Trusted oracle for off-chain verification
Smart Contracts: Audited and verified on blockchain
Payment Reference: Bob must include correct reference in bank transfer


⏱️ Timeline Breakdown
TimeActionActorStatusT+0minBob accepts orderBobOrder AcceptedT+1minBob receives payment instructionsSystemAwaiting PaymentT+5minBob completes bank transferBobPayment PendingT+7minChainlink verifies paymentChainlinkPayment VerifiedT+8minUSDC transferred to BobSmart ContractCompleted ✅
Total Time: ~8 minutes (most time is bank processing)

🚨 Failure Scenarios & Handling
If Bob doesn't pay:

Order expires after 30 minutes
Alice's USDC remains in her wallet
Bob can't claim the USDC

If Bob pays wrong amount:

Chainlink verification fails
Order remains in "Accepted" state
Alice keeps her USDC, Bob keeps his money
Bob can pay the difference or cancel

If Bob forgets payment reference:

Bank transfer won't be matched to order
Verification fails
Trade doesn't execute
Bob can contact support to resolve

If banking API is down:

Chainlink Functions will retry
Order has extended deadline
Manual verification possible as backup

This flow ensures Bob gets exactly what he pays for, while Alice is protected from payment fraud - all without either party needing to trust a centralized exchange! 🎉
