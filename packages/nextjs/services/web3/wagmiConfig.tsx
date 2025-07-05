import { Chain } from "viem";
import { hardhat, mainnet, sepolia } from "viem/chains";
import { http } from "wagmi";
import scaffoldConfig, { DEFAULT_ALCHEMY_API_KEY, ScaffoldConfig } from "~~/scaffold.config";
import { getAlchemyHttpUrl } from "~~/utils/scaffold-eth";
import { createConfig } from '@privy-io/wagmi';

const { targetNetworks } = scaffoldConfig;

// We always want to have mainnet enabled (ENS resolution, ETH price, etc). But only once.
export const enabledChains = targetNetworks.find((network: Chain) => network.id === 1)
  ? targetNetworks
  : ([...targetNetworks, mainnet] as const);

// Create transports for each chain
const createTransports = () => {
  const transports: Record<number, any> = {};
  
  enabledChains.forEach((chain) => {
    const rpcOverrideUrl = (scaffoldConfig.rpcOverrides as ScaffoldConfig["rpcOverrides"])?.[chain.id];
    
    if (rpcOverrideUrl) {
      transports[chain.id] = http(rpcOverrideUrl);
    } else {
      const alchemyHttpUrl = getAlchemyHttpUrl(chain.id);
      if (alchemyHttpUrl) {
        const isUsingDefaultKey = scaffoldConfig.alchemyApiKey === DEFAULT_ALCHEMY_API_KEY;
        // If using default Scaffold-ETH 2 API key, we prioritize the default RPC
        transports[chain.id] = isUsingDefaultKey ? http() : http(alchemyHttpUrl);
      } else {
        transports[chain.id] = http();
      }
    }
  });
  
  return transports;
};

export const wagmiConfig = createConfig({
  chains: enabledChains,
  transports: createTransports(),
  pollingInterval: scaffoldConfig.pollingInterval,
});
