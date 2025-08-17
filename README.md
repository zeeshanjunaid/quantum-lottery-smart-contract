## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Chunked processing & refunds

This project uses a chunked on-chain processing model for draw resolution. When Chainlink VRF returns randomness,
the contract records the random seed and then requires repeated calls to `processDrawChunk(hourId, iterations)` to
complete winner selection and per-player state updates. This avoids a single VRF callback doing work proportional to
the number of participants which can exceed block gas limits.

If a draw cannot be resolved (for example, due to a multi-hour outage) an owner may `forceResolve` the draw which
zeroes the prize pot and marks the draw as force-resolved. Participants may then individually call `claimRefund(hourId)`
to receive their ticket refund. The owner may reclaim unclaimed refunds after a long grace period via
`withdrawUnclaimed(hourId, to)`; this only withdraws the per-draw reserved refund liability and cannot exceed the
contract balance.

Notes about lifecycle and cleanup:

	The contract uses a chunked processing model; the `RESOLVED` status indicates randomness is available and processing
	remains to finish winner selection and payouts.
	individually claim refunds via `claimRefund`, and mappings are cleared when refunds are claimed. `cleanupDrawChunk`
	is intended only for normal draw resolution cleanup.

Notes:
- Force-resolved draws (owner `forceResolveDraw`) set `forceResolved = true` and zero the
	`prizePot`. They intentionally keep the `participants` array intact so individual players
	can claim refunds via `claimRefund`. Because `cleanupDrawChunk` is only used after a
	normal resolution (the contract sets `cleanupPending` during chunked processing), the
	participant array for force-resolved draws will remain until participants claim refunds
	or the owner uses `withdrawUnclaimed` after the long grace period. This is expected
	behavior and not harmful, but it is worth noting for storage visibility.

- The admin may cancel a scheduled cosmic surge using `cancelNextCosmicSurge()` if they
	need to reschedule it later; this avoids re-deploying the contract to overwrite the
	guarded scheduling slot.
