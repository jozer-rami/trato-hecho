"use client";

// @refresh reset
import { Balance } from "../Balance";
import { AddressInfoDropdown } from "./AddressInfoDropdown";
import { AddressQRCodeModal } from "./AddressQRCodeModal";
import { WrongNetworkDropdown } from "./WrongNetworkDropdown";
// import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Address } from "viem";
import { useNetworkColor } from "~~/hooks/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { getBlockExplorerAddressLink } from "~~/utils/scaffold-eth";
import { usePrivy, useWallets } from "@privy-io/react-auth";


/**
 * Custom Wagmi Connect Button (watch balance + custom design)
 */
export const RainbowKitCustomConnectButton = () => {
  const networkColor = useNetworkColor();
  const { targetNetwork } = useTargetNetwork();

  const { login, authenticated, logout, user } = usePrivy();
  const { wallets } = useWallets();
  const activeWallet = wallets?.[0];

  const getChainNumber = (chainId: string | undefined): number => {
    if (!chainId) return 0
    return Number(chainId.split(":")[1]);
  }

  const isWrongNetwork = getChainNumber(activeWallet?.chainId) !== targetNetwork.id;

  function getChainName(chainId: number): string {
    if (!chainId) return "Unknown Network"
    
    const chainNames: Record<number, string> = {
      31337: "Hardhat",
      11155111: "Sepolia",
      84532: "Base Sepolia",
      8453: "Base",
    }
    
    return chainNames[chainId] || "Unknown Network"
  }

  return (
    <>
      {authenticated ? (
        <>
          <div className="flex flex-col items-center mr-1">
            <Balance address={user?.wallet?.address as Address} className="min-h-0 h-auto" />
            <span className="text-xs" style={{ color: networkColor }}>
              {getChainName(getChainNumber(activeWallet?.chainId))}
            </span>
          </div>

          {isWrongNetwork ? (
            <WrongNetworkDropdown />
          ) : (
            <>
              <AddressInfoDropdown
                address={user?.wallet?.address as Address}
                displayName={user?.wallet?.address?.slice(0, 6) + "..." + user?.wallet?.address?.slice(-4)}
                ensAvatar=""
                blockExplorerAddressLink={getBlockExplorerAddressLink(targetNetwork, user?.wallet?.address as Address)}
              />
              <AddressQRCodeModal address={user?.wallet?.address as Address} modalId="qrcode-modal" />
            </>
          )}

          {/* <button 
            className="btn btn-primary btn-sm"
            onClick={() => logout()}
          >
            Logout
          </button> */}
        </>
      ) : (
        <button 
          className="btn btn-primary btn-sm"
          onClick={() => login({ loginMethods: ["wallet"] })}
        >
          Connect Wallet
        </button>
      )}
    </>
  );
};
