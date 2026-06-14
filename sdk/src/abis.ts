export const VAULT_ABI = [
  {
    name: "executePlan",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "actions",
        type: "tuple[]",
        components: [
          { name: "target", type: "address" },
          { name: "callData", type: "bytes" },
          { name: "value", type: "uint256" },
          { name: "tokenIn", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "tokenOut", type: "address" },
        ],
      },
    ],
    outputs: [],
  },
  {
    name: "getCharter",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "pilot", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "pilot", type: "address" },
          { name: "allowedTargets", type: "address[]" },
          { name: "allowedTokensIn", type: "address[]" },
          { name: "allowedTokensOut", type: "address[]" },
          { name: "maxSingleAmountIn", type: "uint256" },
          { name: "maxDailyAmountIn", type: "uint256" },
          { name: "expiresAt", type: "uint256" },
        ],
      },
    ],
  },
  {
    name: "captain",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "isPaused",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "forceWithdrawAll",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "tokens", type: "address[]" },
    ],
    outputs: [],
  },
  {
    name: "ActionExecuted",
    type: "event",
    inputs: [
      { name: "pilot", type: "address", indexed: true },
      {
        name: "action",
        type: "tuple",
        indexed: false,
        components: [
          { name: "target", type: "address" },
          { name: "callData", type: "bytes" },
          { name: "value", type: "uint256" },
          { name: "tokenIn", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "tokenOut", type: "address" },
        ],
      },
      { name: "success", type: "bool", indexed: false },
    ],
  },
  {
    name: "Deposited",
    type: "event",
    inputs: [
      { name: "token", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

export const VAULT_FACTORY_ABI = [
  {
    name: "createVault",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ name: "vault", type: "address" }],
  },
  {
    name: "vaultOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "captain", type: "address" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "allVaultsCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "allVaults",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "start", type: "uint256" },
      { name: "limit", type: "uint256" },
    ],
    outputs: [{ name: "result", type: "address[]" }],
  },
  {
    name: "VaultCreated",
    type: "event",
    inputs: [
      { name: "captain", type: "address", indexed: true },
      { name: "vault", type: "address", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const;

export const PILOT_REGISTRY_ABI = [
  {
    name: "getPilot",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint256" },
          { name: "developer", type: "address" },
          { name: "executor", type: "address" },
          { name: "operator", type: "address" },
          {
            name: "card",
            type: "tuple",
            components: [
              { name: "name", type: "string" },
              { name: "description", type: "string" },
              { name: "riskProfile", type: "string" },
              { name: "ipfsMetadata", type: "string" },
              { name: "supportedChains", type: "address[]" },
            ],
          },
          { name: "stakedAmount", type: "uint256" },
          { name: "active", type: "bool" },
          { name: "slashed", type: "bool" },
          { name: "registeredAt", type: "uint256" },
        ],
      },
    ],
  },
  {
    name: "activePilotCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getActivePilotIds",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "start", type: "uint256" },
      { name: "limit", type: "uint256" },
    ],
    outputs: [{ name: "ids", type: "uint256[]" }],
  },
  {
    name: "PilotRegistered",
    type: "event",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "developer", type: "address", indexed: true },
      { name: "executor", type: "address", indexed: true },
      { name: "operator", type: "address", indexed: false },
      { name: "name", type: "string", indexed: false },
    ],
  },
] as const;

export const ERC8004_REPUTATION_ABI = [
  {
    name: "getScore",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "subject", type: "address" }],
    outputs: [{ name: "", type: "int256" }],
  },
  {
    name: "getFeedbackCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "subject", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const MOCK_ORACLE_ABI = [
  {
    name: "getPrice",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getPrices",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "tokens", type: "address[]" }],
    outputs: [{ name: "prices", type: "uint256[]" }],
  },
  {
    name: "getValue",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "tokenDecimals", type: "uint8" },
    ],
    outputs: [{ name: "valueUSD", type: "uint256" }],
  },
  {
    name: "setPrice",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "priceUSD", type: "uint256" },
      { name: "symbol", type: "string" },
    ],
    outputs: [],
  },
  {
    name: "PriceSet",
    type: "event",
    inputs: [
      { name: "token", type: "address", indexed: true },
      { name: "priceUSD", type: "uint256", indexed: false },
      { name: "symbol", type: "string", indexed: false },
    ],
  },
] as const;

export const ERC20_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
] as const;

export const CONSERVATIVE_RWA_ABI = [
  {
    name: "computeDrifts",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "balances", type: "uint256[]" },
      { name: "targetsBps", type: "uint256[]" },
    ],
    outputs: [{ name: "driftsBps", type: "int256[]" }],
  },
  {
    name: "shouldRebalance",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "driftsBps", type: "int256[]" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "encodeAaveSupply",
    type: "function",
    stateMutability: "pure",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "onBehalfOf", type: "address" },
    ],
    outputs: [{ name: "", type: "bytes" }],
  },
  {
    name: "encodeAaveWithdraw",
    type: "function",
    stateMutability: "pure",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "to", type: "address" },
    ],
    outputs: [{ name: "", type: "bytes" }],
  },
  {
    name: "DRIFT_THRESHOLD_BPS",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
