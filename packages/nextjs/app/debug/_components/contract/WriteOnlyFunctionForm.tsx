"use client";

import { useEffect, useState } from "react";
import { InheritanceTooltip } from "./InheritanceTooltip";
import { Abi, AbiFunction } from "abitype";
import { Address, TransactionReceipt, encodeFunctionData } from "viem";
import { useWaitForTransactionReceipt, useSendTransaction } from "wagmi";
import { useWallets } from "@privy-io/react-auth";
import {
  ContractInput,
  TxReceipt,
  getFunctionInputKey,
  getInitialFormState,
  getParsedContractFunctionArgs,
  transformAbiFunction,
} from "~~/app/debug/_components/contract";
import { IntegerInput } from "~~/components/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";

type WriteOnlyFunctionFormProps = {
  abi: Abi;
  abiFunction: AbiFunction;
  onChange: () => void;
  contractAddress: Address;
  inheritedFrom?: string;
};

export const WriteOnlyFunctionForm = ({
  abi,
  abiFunction,
  onChange,
  contractAddress,
  inheritedFrom,
}: WriteOnlyFunctionFormProps) => {
  const [form, setForm] = useState<Record<string, any>>(() => getInitialFormState(abiFunction));
  const [txValue, setTxValue] = useState<string>("");
  const [result, setResult] = useState<string | undefined>();
  const { wallets } = useWallets();
  const activeWallet = wallets?.[0];
  const { targetNetwork } = useTargetNetwork();
  
  const getChainNumber = (chainId: string | undefined): number => {
    if (!chainId) return 0;
    return Number(chainId.split(":")[1]);
  };
  
  const writeDisabled = !activeWallet || getChainNumber(activeWallet?.chainId) !== targetNetwork.id;

  // Use wagmi's useSendTransaction hook (recommended by Privy)
  const { sendTransaction, isPending, error } = useSendTransaction();

  const handleWrite = async () => {
    if (activeWallet && !writeDisabled) {
      try {
        // Encode the function call data
        const args = getParsedContractFunctionArgs(form);
        const data = encodeFunctionData({
          abi: abi,
          functionName: abiFunction.name,
          args: args,
        });

        console.log('Active wallet:', activeWallet);
        console.log('Encoded data:', data);
        console.log('Contract address:', contractAddress);
        console.log('Value:', txValue);

        // Use wagmi's sendTransaction hook
        sendTransaction({
          to: contractAddress,
          data: data,
          value: txValue ? BigInt(txValue) : undefined,
        }, {
          onSuccess: (hash: `0x${string}`) => {
            console.log('Transaction hash:', hash);
            setResult(hash);
            onChange();
          },
          onError: (error: any) => {
            console.error('Transaction failed:', error);
            alert(`Transaction failed: ${error.message}`);
          }
        });
      } catch (e: any) {
        console.error("⚡️ ~ file: WriteOnlyFunctionForm.tsx:handleWrite ~ error", e);
        alert(`Transaction failed: ${e.message || 'Unknown error'}`);
      }
    }
  };

  const [displayedTxResult, setDisplayedTxResult] = useState<TransactionReceipt>();
  const { data: txResult } = useWaitForTransactionReceipt({
    hash: result as `0x${string}`,
  });
  useEffect(() => {
    setDisplayedTxResult(txResult);
  }, [txResult]);

  // TODO use `useMemo` to optimize also update in ReadOnlyFunctionForm
  const transformedFunction = transformAbiFunction(abiFunction);
  const inputs = transformedFunction.inputs.map((input: any, inputIndex: number) => {
    const key = getFunctionInputKey(abiFunction.name, input, inputIndex);
    return (
      <ContractInput
        key={key}
        setForm={updatedFormValue => {
          setDisplayedTxResult(undefined);
          setForm(updatedFormValue);
        }}
        form={form}
        stateObjectKey={key}
        paramType={input}
      />
    );
  });
  const zeroInputs = inputs.length === 0 && abiFunction.stateMutability !== "payable";

  return (
    <div className="py-5 space-y-3 first:pt-0 last:pb-1">
      <div className={`flex gap-3 ${zeroInputs ? "flex-row justify-between items-center" : "flex-col"}`}>
        <p className="font-medium my-0 break-words">
          {abiFunction.name}
          <InheritanceTooltip inheritedFrom={inheritedFrom} />
        </p>
        {inputs}
        {abiFunction.stateMutability === "payable" ? (
          <div className="flex flex-col gap-1.5 w-full">
            <div className="flex items-center ml-2">
              <span className="text-xs font-medium mr-2 leading-none">payable value</span>
              <span className="block text-xs font-extralight leading-none">wei</span>
            </div>
            <IntegerInput
              value={txValue}
              onChange={updatedTxValue => {
                setDisplayedTxResult(undefined);
                setTxValue(updatedTxValue);
              }}
              placeholder="value (wei)"
            />
          </div>
        ) : null}
        <div className="flex justify-between gap-2">
          {!zeroInputs && (
            <div className="grow basis-0">{displayedTxResult ? <TxReceipt txResult={displayedTxResult} /> : null}</div>
          )}
          <div
            className={`flex ${
              writeDisabled &&
              "tooltip tooltip-bottom tooltip-secondary before:content-[attr(data-tip)] before:-translate-x-1/3 before:left-auto before:transform-none"
            }`}
            data-tip={`${writeDisabled && "Wallet not connected or in the wrong network"}`}
          >
            <button className="btn btn-secondary btn-sm" disabled={writeDisabled || isPending} onClick={handleWrite}>
              {isPending && <span className="loading loading-spinner loading-xs"></span>}
              Send 💸
            </button>
          </div>
        </div>
      </div>
      {zeroInputs && txResult ? (
        <div className="grow basis-0">
          <TxReceipt txResult={txResult} />
        </div>
      ) : null}
    </div>
  );
};
