import { encodeFunctionData, type Address } from "viem";

const AAVE_SUPPLY_ABI = [
  {
    name: "supply",
    type: "function",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "onBehalfOf", type: "address" },
      { name: "referralCode", type: "uint16" },
    ],
  },
] as const;

const AAVE_WITHDRAW_ABI = [
  {
    name: "withdraw",
    type: "function",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "to", type: "address" },
    ],
  },
] as const;

export function encodeAaveSupply(
  asset: Address,
  amount: bigint,
  vault: Address,
): `0x${string}` {
  return encodeFunctionData({
    abi: AAVE_SUPPLY_ABI,
    functionName: "supply",
    args: [asset, amount, vault, 0],
  });
}

export function encodeAaveWithdraw(
  asset: Address,
  amount: bigint,
  vault: Address,
): `0x${string}` {
  return encodeFunctionData({
    abi: AAVE_WITHDRAW_ABI,
    functionName: "withdraw",
    args: [asset, amount, vault],
  });
}
