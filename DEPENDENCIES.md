# Vendored dependencies

The repository includes the following dependencies as ordinary source files. No
submodules or build-time downloads are used. Imports resolve through
`remappings.txt`. Vendored upstream source files are unmodified.

| Library | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | v5.0.2 | The nine-file transitive import closure of ERC20, SafeERC20, and ReentrancyGuard under `lib/openzeppelin-contracts/contracts/` | `lib/openzeppelin-contracts/LICENSE` (MIT) |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | v1.9.7 | Complete `src/` under `lib/forge-std/` | `lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE` (MIT or Apache-2.0) |

SHA-256 of the upstream release archives used to populate these files:

```text
https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a

https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
```

Foundry and the pinned solc 0.8.26 are execution tools supplied by the checking
environment, not vendored binaries. The application requires no external services.
