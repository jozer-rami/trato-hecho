/* eslint-disable prettier/prettier */
import type {PrivyClientConfig} from '@privy-io/react-auth';
import { localhost, baseSepolia, sepolia, mainnet, Chain } from 'viem/chains';

// Custom Hardhat chain configuration
// const hardhatChain: Chain = {
//   id: 31337,
//   name: 'Hardhat',
//   network: 'hardhat',
//   nativeCurrency: {
//     decimals: 18,
//     name: 'Ether',
//     symbol: 'ETH',
//   },
//   rpcUrls: {
//     default: { 
//       http: ['http://127.0.0.1:8545']
//     },
//     public: {
//       http: ['http://127.0.0.1:8545']
//     }
//   }
// }

// Replace this with your Privy config
export const privyConfig: PrivyClientConfig = {
  embeddedWallets: {
    createOnLogin: 'users-without-wallets',
    requireUserPasswordOnCreate: true,
    showWalletUIs: true,
  },
  loginMethods: ['wallet', 'email', 'sms'],
  appearance: {
    showWalletLoginFirst: true,
  },
  supportedChains: [mainnet, sepolia],
};