"use client";

import { useEffect, useState } from "react";
// import { RainbowKitProvider, darkTheme, lightTheme } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AppProgressBar as ProgressBar } from "next-nprogress-bar";
import { useTheme } from "next-themes";
import { Toaster } from "react-hot-toast";
import { Footer } from "~~/components/Footer";
import { Header } from "~~/components/Header";
// import { BlockieAvatar } from "~~/components/scaffold-eth";
import { useInitializeNativeCurrencyPrice } from "~~/hooks/scaffold-eth";
import { wagmiConfig } from "~~/services/web3/wagmiConfig";
import { PrivyProvider } from "@privy-io/react-auth";
import { WagmiProvider } from "@privy-io/wagmi";
import { privyConfig } from "~~/services/web3/privyConfig";


const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  useInitializeNativeCurrencyPrice();

  return (
    <>
      <div className={`flex flex-col min-h-screen `}>
        <Header />
        <main className="relative flex flex-col flex-1">{children}</main>
        <Footer />
      </div>
      <Toaster />
    </>
  );
};

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
    },
  },
});

export const ScaffoldEthAppWithProviders = ({ children }: { children: React.ReactNode }) => {
  const { resolvedTheme } = useTheme();
  const isDarkMode = resolvedTheme === "dark";
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <QueryClientProvider client={queryClient}>
      <PrivyProvider appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID as string} config={privyConfig}>
        <WagmiProvider config={wagmiConfig}>
          <ProgressBar height="3px" color="#2299dd" />
          {/* <RainbowKitProvider
            avatar={BlockieAvatar}
            theme={mounted ? (isDarkMode ? darkTheme() : lightTheme()) : lightTheme()}
          > */}
            <ScaffoldEthApp>{children}</ScaffoldEthApp>
          {/* </RainbowKitProvider> */}
        </WagmiProvider>
      </PrivyProvider>
    </QueryClientProvider>
  );
};
