# Vultisig — Product Context

## What is Vultisig

Vultisig is a **seedless, multi-chain crypto wallet** powered by multi-party
computation (MPC). It's the first wallet built for both humans and AI agents.

**Key differentiators:**
- **No seed phrases.** Uses MPC/TSS (threshold signature scheme) instead of
  traditional seed phrase backup. Vault keys are split across 2+ devices.
- **Multi-chain native.** Supports 30+ blockchains (EVM, UTXO, Cosmos, Solana,
  THORChain, etc.) from a single vault.
- **Agentic architecture.** Designed for AI agents to hold and manage crypto
  assets programmatically.
- **Open-source.** All code is public. Free to use.

## Core Concepts

| Concept | Definition |
|---------|------------|
| **Vault** | A multi-device wallet. Keys are split across 2+ parties via MPC. |
| **Party** | One device/participant holding a key share. |
| **Threshold** | Minimum parties needed to sign (e.g., 2-of-3). |
| **Keygen** | Initial vault creation — generates key shares across parties. |
| **Keysign** | Transaction signing — threshold parties cooperate to produce a signature. |
| **Reshare** | Re-distributing key shares (add/remove devices, change threshold). |
| **DKLS23** | The MPC protocol Vultisig uses for ECDSA chains (Bitcoin, Ethereum, etc.). |
| **ML-DSA** | Post-quantum threshold signature scheme for future-proofing. |

## Architecture

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   iOS App   │  │ Android App │  │ Windows App │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                  ┌─────┴─────┐
                  │   Relay   │  ← Multi-device communication
                  └─────┬─────┘
                        │
              ┌─────────┴─────────┐
              │                   │
        ┌─────┴─────┐     ┌──────┴──────┐
        │ Vultiserver│     │     SDK     │
        │ (signing)  │     │ (TypeScript)│
        └─────┬─────┘     └──────┬──────┘
              │                   │
        ┌─────┴─────┐     ┌──────┴──────┐
        │  MPC Libs  │     │  Plugins    │
        │ dkls23-rs  │     │ fee, agent  │
        │ ml-dsa-tss │     │ marketplace │
        └───────────┘     └─────────────┘
```

## Repos You'll Work On

See `brain/repos/index.md` for the full list. Key ones:

| Repo | Language | What it does |
|------|----------|-------------|
| vultisig-sdk | TypeScript | SDK for MPC wallet operations (keygen, keysign, reshare) |
| vultisig-windows | TypeScript | Windows desktop app (Wails + React) |
| vultisig-ios | Swift | iOS mobile app |
| vultisig-android | Kotlin | Android mobile app |
| commondata | Go | Shared data structures (protobuf, chain configs) |
| vultiserver | Go | Server-side MPC signing service |

## What to Be Careful About

- **Signing code** is the most sensitive. A bug can lose funds.
- **Key handling** — never log, expose, or mishandle key shares.
- **Chain-specific logic** — each blockchain has different rules for addresses,
  transactions, fees. Don't assume EVM patterns apply to UTXO or Cosmos.
- **Protobuf schemas** — `commondata` defines shared types. Changes there
  ripple across all apps.
