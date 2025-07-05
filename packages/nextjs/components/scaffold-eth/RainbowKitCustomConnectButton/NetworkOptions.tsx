import { useTheme } from "next-themes";
import { usePrivy, useWallets } from "@privy-io/react-auth";
import { ArrowsRightLeftIcon } from "@heroicons/react/24/solid";
import { getNetworkColor } from "~~/hooks/scaffold-eth";
import { getTargetNetworks } from "~~/utils/scaffold-eth";

const allowedNetworks = getTargetNetworks();

type NetworkOptionsProps = {
  hidden?: boolean;
};

export const NetworkOptions = ({ hidden = false }: NetworkOptionsProps) => {
  // const { switchChain } = useSwitchChain();
  const { wallets } = useWallets();
  const { resolvedTheme } = useTheme();
  const isDarkMode = resolvedTheme === "dark";

  const activeWallet = wallets?.[0];

  console.log("activeWallet", activeWallet);

  const getChainNumber = (chainId: string | undefined): number => {
    if (!chainId) return 0
    return Number(chainId.split(":")[1]);
  }

  const handleNetworkSwitch = async (chainId: number) => {
    if (!activeWallet) return;

    try {
      await activeWallet.switchChain(chainId);
    } catch (error: any) {
      console.error('Failed to switch network:', error);
    }
  };

  return (
    <>
      {allowedNetworks
        .filter(allowedNetwork => allowedNetwork.id !== getChainNumber(activeWallet?.chainId))
        .map(allowedNetwork => (
          <li key={allowedNetwork.id} className={hidden ? "hidden" : ""}>
            <button
              className="menu-item btn-sm rounded-xl! flex gap-3 py-3 whitespace-nowrap"
              type="button"
              onClick={() => handleNetworkSwitch(allowedNetwork.id)}
            >
              <ArrowsRightLeftIcon className="h-6 w-4 ml-2 sm:ml-0" />
              <span>
                Switch to{" "}
                <span
                  style={{
                    color: getNetworkColor(allowedNetwork, isDarkMode),
                  }}
                >
                  {allowedNetwork.name}
                </span>
              </span>
            </button>
          </li>
        ))}
    </>
  );
};
