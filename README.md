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

# TratoHechoP2P_CCTP

A peer-to-peer USDC trading platform with EIP-7702 integration for seamless cross-chain settlements via Circle's Cross-Chain Transfer Protocol (CCTP).

## Overview

TratoHechoP2P_CCTP enables users to trade USDC for fiat currency across multiple blockchain networks. The platform introduces **EIP-7702 "temporary delegation"** to eliminate manual escrow steps, allowing automatic settlement once payment verification is complete.

### Key Features

- **EIP-7702 Integration**: Sellers can delegate temporary authorization instead of locking funds in escrow
- **Automatic Settlement**: Smart contract automatically transfers USDC when payment is verified
- **Cross-Chain Support**: Seamless USDC transfers across chains via Circle CCTP
- **Oracle-Verified Payments**: Chainlink integration for reliable fiat payment verification
- **Backwards Compatible**: Traditional escrow flow remains available for all users

## How It Works

### EIP-7702 Enhanced Flow (Recommended)

1. **Seller Creates Order**: Signs an EIP-7702 delegation and creates a sell order without escrowing funds
2. **Buyer Accepts**: Buyer accepts the order and makes fiat payment off-chain
3. **Payment Verification**: Chainlink oracle verifies the fiat payment through banking APIs
4. **Automatic Settlement**: Contract uses AUTHCALL to automatically transfer seller's USDC to buyer

### Traditional Escrow Flow (Legacy Support)

1. **Seller Escrows**: Seller approves and deposits USDC into the contract
2. **Buyer Accepts**: Buyer accepts order and makes fiat payment
3. **Payment Verification**: Oracle verifies payment
4. **Manual Completion**: Seller manually calls `completeOrder()` to release funds

## Smart Contract Architecture

### Core Components

- **Order Creation**: Handles both delegation-based and escrow-based order creation
- **Order Management**: Manages order lifecycle, acceptance, and status tracking
- **EIP-7702 Handler**: Validates delegations and executes AUTHCALL operations
- **Payment Verification**: Interfaces with Chainlink oracle for payment confirmation
- **Auto Settlement**: Automatically settles orders using seller delegations
- **Cross-Chain Settlement**: Integrates with Circle CCTP for multi-chain transfers
- **Escrow System**: Traditional escrow support for backwards compatibility

### Key Data Structures

```solidity
struct Order {
    uint256 id;
    address seller;
    address buyer;
    uint256 amountUSDC;
    uint256 priceFiat;
    uint256 deadline;
    OrderStatus status;
    bool isCrossChain;
}

struct Delegation {
    address delegate;      // P2P contract address
    uint64  expiry;        // Unix timestamp
    bytes32 salt;          // Replay protection
    bytes   signature;     // EIP-712 signature
}

struct DelegatedAuth {
    Delegation delegation;
    bool active;
}
```

## Installation & Setup

### Prerequisites

- Node.js v18+
- Hardhat or Foundry
- EIP-7702 compatible wallet (future requirement)

### Installation

```bash
git clone https://github.com/your-org/TratoHechoP2P_CCTP.git
cd TratoHechoP2P_CCTP
npm install
```

### Environment Setup

Create a `.env` file:

```env
PRIVATE_KEY=your_private_key
CHAINLINK_ORACLE_ADDRESS=0x...
USDC_TOKEN_ADDRESS=0x...
CCTP_TOKEN_MESSENGER=0x...
```

### Deployment

```bash
# Deploy to testnet
npx hardhat deploy --network sepolia

# Deploy to mainnet
npx hardhat deploy --network mainnet
```

## Usage

### For Sellers

#### Create Order with EIP-7702 Delegation

```solidity
// Sign delegation (handled by wallet)
Delegation memory delegation = Delegation({
    delegate: address(tratomp2pContract),
    expiry: block.timestamp + 24 hours,
    salt: keccak256(abi.encode(block.timestamp, msg.sender)),
    signature: // EIP-712 signature from wallet
});

// Create order without escrow
uint256 orderId = tratoP2P.createSellOrder7702(
    1000e6,  // 1000 USDC
    50000,   // 50,000 units of fiat
    block.timestamp + 1 days,
    delegation
);
```

#### Create Order with Traditional Escrow

```solidity
// Approve and create order with escrow
usdcToken.approve(address(tratoP2P), 1000e6);
uint256 orderId = tratoP2P.createSellOrder(
    1000e6,  // 1000 USDC
    50000,   // 50,000 units of fiat
    block.timestamp + 1 days
);
```

### For Buyers

```solidity
// Accept order
tratoP2P.acceptOrder(orderId, destinationDomain);

// After making fiat payment, verify payment
tratoP2P.verifyPayment(orderId, "payment_reference_id");
```

## Security Features

### EIP-7702 Safety Mechanisms

- **Time-Bounded Delegations**: All delegations include expiry timestamps
- **Revocation Support**: Sellers can revoke delegations at any time via new 7702 transaction
- **Single-Use Protection**: Salt prevents delegation replay attacks
- **Contract-Specific**: Delegations are tied to specific contract addresses

### General Security

- **Oracle Verification**: All payments verified through Chainlink before settlement
- **Reentrancy Protection**: ReentrancyGuard on all state-changing functions
- **Access Controls**: Role-based permissions for administrative functions
- **Emergency Pause**: Circuit breaker for emergency situations

## Cross-Chain Support

The platform supports USDC transfers across multiple chains via Circle CCTP:

- Ethereum
- Arbitrum
- Optimism
- Polygon
- Avalanche
- Base

### Cross-Chain Flow

1. Contract receives USDC from seller (via AUTHCALL or escrow)
2. Burns USDC on source chain via CCTP
3. Mints equivalent USDC on destination chain
4. Buyer receives USDC on their preferred chain

## Oracle Integration

### Supported Payment Methods

- Bank transfers (ACH, wire, SEPA)
- Mobile money (M-Pesa, GCash, etc.)
- Digital wallets (PayPal, Venmo, etc.)
- Credit/debit cards

### Verification Process

1. Buyer provides payment reference ID
2. Chainlink oracle queries relevant APIs
3. Oracle confirms payment status and amount
4. Contract receives verification result
5. Automatic settlement triggered on success

## Development Roadmap

### Phase 1: Core Implementation ✅
- [x] Basic P2P trading functionality
- [x] Chainlink oracle integration
- [x] Circle CCTP integration

### Phase 2: EIP-7702 Integration 🚧
- [ ] EIP-7702 delegation handling
- [ ] AUTHCALL implementation
- [ ] Wallet integration for delegation signing
- [ ] Comprehensive testing

### Phase 3: Production Ready 📋
- [ ] Multi-chain deployment
- [ ] Advanced security audits
- [ ] Mobile wallet support
- [ ] Enhanced UI/UX

### Phase 4: Advanced Features 📋
- [ ] Partial order fills
- [ ] Order books
- [ ] Reputation system
- [ ] Governance token

## Testing

```bash
# Run unit tests
npm run test

# Run integration tests
npm run test:integration

# Run coverage
npm run coverage

# Test EIP-7702 functionality (requires compatible testnet)
npm run test:eip7702
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Circle CCTP](https://developers.circle.com/stablecoin/docs/cctp-getting-started) for cross-chain infrastructure
- [Chainlink](https://chain.link/) for reliable oracle services
- [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) for account abstraction capabilities

## Support

For questions and support:
- Create an issue in this repository
- Join our Discord: [discord.gg/tratohechop2p](#)
- Email: support@tratohechop2p.com

---

**Note**: EIP-7702 is currently in development. Production deployment should wait for mainnet activation and wallet support.