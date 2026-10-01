# Token-paid guestbook

An immutable, append-only onchain guestbook. Each call to `sign` transfers exactly
10 launch tokens from the caller to `0x000000000000000000000000000000000000dEaD`
and stores the caller, message, and block timestamp. Failed payments and invalid
messages leave both entries and token balances unchanged.

## Build and test

Requires Foundry and Solidity **0.8.26**, pinned in `foundry.toml`. All Solidity
dependencies are vendored as ordinary files under `lib/`; no package installation,
submodule, RPC, wallet, environment configuration, FFI, or filesystem cheatcode
permission is needed. With the compiler installed, builds and tests work offline.

```sh
forge build
forge test
forge fmt --check
```

The compiler targets the Paris EVM, with optimization enabled (200 runs) and
`bytecode_hash = "none"` for launch compatibility. Tests use isolated local EVMs
and can run in parallel. Unit and fuzz tests cover payment, storage, indexes,
events, allowance and balance failures, byte boundaries, Unicode, contract callers,
donations, and repeated signing. Adversarial token fixtures cover false returns,
missing return data, insufficient receipt, payment reverts, and reentrant callbacks.
Stateful invariants check conservation and the complete entry history across
128 runs of 32 calls. Deployment tests execute CREATE2 constructors and scan
runtime code for size limits and forbidden opcodes.

## Contracts and deployment parameters

| Order | Artifact | Nonpayable constructor arguments |
| --- | --- | --- |
| 1 | `src/LaunchToken.sol:LaunchToken` | None |
| 2 | `src/Guestbook.sol:Guestbook` | `address token_`: the deployed launch token (`$token`) |

`LaunchToken` is a plain OpenZeppelin ERC-20 named **Guestbook Token**, symbol
**GUEST**, with 18 decimals. The brief's `$token` is interpreted as the launch
token reference; it does not specify a literal name or ticker. Exactly
1,000,000,000 tokens (`10^27` minor units) are minted to the constructor caller.
Under ProjectFactory that caller is the factory, which distributes the supply.
The token has no externally callable mint or burn, owner, fees, pause, blocklist,
or upgrade mechanism.

The guestbook is fully configured by its constructor. It neither moves the launch
supply during deployment nor assigns privileges to its deployer. For the launch
manifest handoff, use `LaunchToken` as the token and one application identifier,
`Guestbook`, with constructor arguments `[$token]` (the reference is a string in
JSON). There are no other application dependencies, initialization calls, owner
arguments, or ETH deployment values. The separate manifest step writes
`launch.json`; it is not supplied here.

The constructor rejects addresses without code and tokens reporting decimals
other than 18. These checks do not authenticate token code. The deployer must
resolve `$token` to this project's actual `LaunchToken`, on the intended chain,
and verify the resulting `token()` value and deployed bytecode. No transactions
were broadcast as part of this implementation.

## Using the guestbook

From the account that will sign:

1. Call `LaunchToken.approve(guestbookAddress, 10000000000000000000)`.
2. Call `Guestbook.sign("Your message")`, sending no ETH. Gas is paid separately.
3. Read `entryCount()` and `entries(index)`. Indexes start at zero; the getter
   returns `(address signer, string message, uint256 timestamp)` and reverts for
   an index at or above the current count.

`sign` returns the new index and emits
`EntrySigned(uint256 indexed index, address indexed signer, string message, uint256 timestamp)`.
Offchain clients can discover the assigned index from the transaction receipt.
The fee, byte limit, burn address, and token address are public getters.
The signer is always `msg.sender`, including for contract wallets. Approving the
guestbook does not let another account submit or pay on the approver's behalf.

## Assumptions and operations

- The limit is **280 bytes**, measured with `bytes(message).length`, not 280
  characters. UTF-8 characters can use multiple bytes. Empty messages and repeated
  messages are allowed and each costs ten tokens. Solidity strings may contain
  arbitrary bytes; no UTF-8 or content validation is performed.
- “Burn” means a transfer to the specified dead address. It relies on the usual
  assumption that no one controls that address. **`totalSupply()` stays fixed**;
  the dead address's balance rises by ten tokens per entry. This fulfills the
  requested destination without adding a supply-changing token function.
- The only supported production payment asset is the provided, immutable launch
  token. The contract checks transfer success and the burn address's exact balance
  increase. Fee-on-transfer, rebasing, upgradeable, and malicious replacement
  tokens are outside the deployment assumptions; a malicious token could lie
  about balances. The guard rejects reentrant signing during token calls.
- The guestbook retains no signing fees. Direct token transfers to it do not
  create entries, and accidentally sent tokens cannot be recovered. Ordinary ETH
  transfers are rejected; forcibly sent ETH also has no recovery mechanism.
- There are no administrators, fee setters, moderators, upgrades, withdrawals,
  refunds, or maintenance jobs. Entries are public and permanent. A correction is
  a new paid entry; failed transactions can still consume gas.
- Timestamps are block timestamps in Unix seconds, subject to the chain's block
  production rules. Entries in one block can share a timestamp; their indexes
  reflect transaction execution order. Timestamps are not an identity or timing
  oracle, and a recorded address is not proof of a real-world identity.
- Client operators must count encoded bytes, display the fee, obtain explicit
  token approvals, render messages as untrusted text, and handle transaction
  failures and reorganizations. Read individual indexes or paginate offchain;
  there is no unbounded onchain enumeration call.
- The network deployer is responsible for the manifest, target-chain selection,
  factory deployment and distribution, published addresses, and explorer source
  verification. Users acquire their own tokens and gas. No funded wallet or
  operator key is required by this project.

The local security review focused on payment atomicity, allowance isolation,
reentrancy, fixed supply, and immutable configuration. Foundry unit, fuzz,
invariant, and deployment checks were run; Slither and Mythril were not run.
These checks are not an independent audit. Independent adversarial review of
the source and final deployment arguments remains a release responsibility.

Dependency versions, provenance, and licenses are recorded in
[`DEPENDENCIES.md`](DEPENDENCIES.md).
