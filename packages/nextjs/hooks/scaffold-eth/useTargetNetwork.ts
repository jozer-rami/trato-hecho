/* eslint-disable prettier/prettier */
import { useWallets } from "@privy-io/react-auth";
import { useEffect, useMemo } from "react";
import { useAccount } from "wagmi";
import scaffoldConfig from "~~/scaffold.config";
import { useGlobalState } from "~~/services/store/store";
import { ChainWithAttributes } from "~~/utils/scaffold-eth";
import { NETWORKS_EXTRA_DATA } from "~~/utils/scaffold-eth";

/**
 * Retrieves the connected wallet's network from scaffold.config or defaults to the 0th network in the list if the wallet is not connected.
 */
export function useTargetNetwork(): { targetNetwork: ChainWithAttributes } {

  const { wallets } = useWallets();
  const activeWallet = wallets?.[0];

  const getChainNumber = (chainId: string | undefined): number => {
    if (!chainId) return 0
    return Number(chainId.split(":")[1]);
  };
  // const { chain } = useAccount();

  const targetNetwork = useGlobalState(({ targetNetwork }) => targetNetwork);
  const setTargetNetwork = useGlobalState(({ setTargetNetwork }) => setTargetNetwork);

  console.log("targetNetwork", targetNetwork.id);
  console.log("activeWallet chainId", activeWallet?.chainId);
  console.log("getChainNumber", getChainNumber(activeWallet?.chainId));

  useEffect(() => {
    const newSelectedNetwork = scaffoldConfig.targetNetworks.find(targetNetwork => targetNetwork.id === getChainNumber(activeWallet?.chainId));
    if (newSelectedNetwork && newSelectedNetwork.id !== targetNetwork.id) {
      setTargetNetwork(newSelectedNetwork);
    }
  }, [activeWallet?.chainId, setTargetNetwork, targetNetwork.id]);

  return useMemo(
    () => ({
      targetNetwork: {
        ...targetNetwork,
        ...NETWORKS_EXTRA_DATA[targetNetwork.id],
      },
    }),
    [targetNetwork],
  );
}