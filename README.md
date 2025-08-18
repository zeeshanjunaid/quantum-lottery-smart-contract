## Quantum Lottery — Smart Contracts (Foundry)

Modular, gas-aware lottery contracts with Chainlink VRF, chunked processing, Q-score streaks, and refund safety. Built with Foundry, OpenZeppelin, and Chainlink VRF v2.

### Highlights
- Thin wrapper `QuantumLottery.sol` with `QuantumLotteryBase.sol` implementation for clean codegen and coverage
- Concern-specific libraries to keep functions small, testable, and gas-efficient
- Chainlink VRF v2 integration and chunked post-fulfillment processing to avoid block gas limits
- Two ticket types (Standard/Quantum), Q-score streak system, and a “cosmic surge” multiplier window
- Safe refund flow for force-resolved draws and guarded withdrawal of unclaimed refunds

## Architecture

- `src/QuantumLottery.sol`: Thin wrapper that inherits `QuantumLotteryBase` and forwards constructor args
- `src/QuantumLotteryBase.sol`: Core implementation, events, and external/public API
- `src/QuantumLotteryTypes.sol`: Enums, structs, events, and constants
- Libraries (separation of concerns):
	- `QuantumLotteryProcessor.sol`: draw processing, winner updates, payouts
	- `QuantumLotteryFulfillment.sol`: randomness fulfillment + total Q-score calc
	- `QuantumLotteryEntry.sol`: ticket purchase and accounting
	- `QuantumLotteryCleanup.sol`: storage cleanup in chunks
	- `QuantumLotteryRefunds.sol`: CEI-compliant refund logic
	- `QuantumLotteryWithdraw.sol`: compute and zero unclaimed refunds
	- `QuantumLotteryForceResolve.sol`: forceful resolution if VRF stalls
	- `QuantumLotteryHelpers.sol`: Q-score increase helper

Core dependencies:
- Solidity ^0.8.20
- OpenZeppelin (Ownable v5, ReentrancyGuard, IERC20, SafeERC20, Math)
- Chainlink VRF v2 (coordinator + consumer base)

## Key constants (see `QuantumLotteryTypes.sol`)
- Standard ticket: `STANDARD_TICKET_PRICE = 1_000_000` (1 USDC, 6 decimals)
- Quantum ticket: `QUANTUM_TICKET_PRICE = 3_000_000` (3 USDC)
- Winner payout percent: `WINNER_PAYOUT_PERCENT = 92` (treasury fee 8%)
- Max Q-score: `MAX_QSCORE = 100_000`
- Seconds per hour: `SECONDS_PER_HOUR = 3600`
- VRF gas limit: `CALLBACK_GAS_LIMIT = 2_500_000`

## Draw lifecycle
1) OPEN: Users call `buyTicket(ticketType)` to join the current hour’s draw
2) CALCULATING_WINNER: Owner calls `requestRandomWinner(hourId)` for a past hour; VRF request sent
3) RESOLVING: On VRF callback, randomness is recorded; chunked processing is required to finish
4) RESOLVED: After `processDrawChunk(hourId, iterations)` completes, payouts are done and `cleanupPending = true`
5) Cleanup: Call `cleanupDrawChunk(hourId, iterations)` until it completes to clear per-draw mappings

Why chunks? Large draws can’t do all work in a single transaction (block gas limits). We split winner selection and per-player updates across multiple calls.

## Refunds and force-resolve
- If a draw is stuck in CALCULATING_WINNER beyond `DRAW_RESOLUTION_TIMEOUT`, the owner can `forceResolveDraw(hourId)`
- Force resolve zeros the prize pot and allows each participant to `claimRefund(hourId)` individually
- After `UNCLAIMED_REFUND_PERIOD`, the owner can sweep remaining liability with `withdrawUnclaimed(hourId, to)`
- Refunds follow CEI: state is updated first; transfer is executed in a separate internal function

## Admin operations
- `requestRandomWinner(hourId)`: request randomness (hour must be in the past, with participants)
- `processDrawChunk(hourId, iterations)`: finish winner selection and post-winner updates; emits `WinnerPicked` when done
- `cleanupDrawChunk(hourId, iterations)`: clear per-draw mapping entries after normal resolution
- `setNextCosmicSurge(timestamp)`, `cancelNextCosmicSurge()`: schedule/cancel a surge window
- `forceResolveDraw(hourId)`: resolve a stuck draw after timeout (enables refunds)
- `withdrawUnclaimed(hourId, to)`: sweep unclaimed refunds after grace period
- `emergencyWithdraw(token, amount)`: owner-only token recovery

## Events
- `TicketPurchased(hourId, player, ticketType, qScoreOnEntry)`
- `WinnerSelectionRequested(hourId, requestId)`
- `RandomnessFulfilled(hourId, requestId, totalQScoreInPool)`
- `WinnerPicked(hourId, winner, prizeAmount, feeAmount, totalQScoreInPool)`
- `QScoreCapped(player, hourId, cappedAt)`
- `RefundIssued(hourId, player, amount, remainingLiability)`
- `WithdrawUnclaimed(hourId, to, amount, remainingLiability)`
- `DrawForceResolved(hourId)` / `DrawForceResolvedWithCount(hourId, participantCount)`
- `CosmicSurgeScheduled(hourId)` / `CosmicSurgeCanceled(hourId)`

## Development

Prereqs: Foundry installed

Build
```bash
forge build
```

Test (66 tests including fuzz)
```bash
forge test -vv
```

Gas snapshot (optional)
```bash
forge snapshot
```

Static analysis (optional)
```bash
# Requires slither installed via pip
slither . --compile-force-framework forge --exclude-dependencies
```

## Deployment

Scripts:
- `script/Deploy.s.sol`: deploy `TestUSDC` (optional) and `QuantumLottery`
- `script/TestUSDC.s.sol`: deploy a 6-decimals mock USDC for local/testing

Example (fill in your values):
```bash
forge script script/Deploy.s.sol:Deploy \
	--rpc-url $RPC_URL \
	--private-key $PRIVATE_KEY \
	--broadcast \
	--verify # optional, if configured
```

Constructor args for `QuantumLottery`:
- usdcAddress (IERC20, 6 decimals)
- treasuryAddress
- vrfCoordinator
- subscriptionId (uint64)
- gasLane (bytes32)

Tip: On testnets you can deploy `TestUSDC` and mint test balances. Ticket prices are set in 6 decimals (1 USDC = 1_000_000).

### Testnet deployment (Arbitrum Sepolia 421614)

1) Copy `.env.example` to `.env` and fill values:
	 - `RPC_URL`: Your Arbitrum Sepolia endpoint
	 - `PRIVATE_KEY`: Deployer key with test ETH
	 - `USDC_ADDRESS`: Use real test USDC or deploy `TestUSDC` (next step)
	 - `TREASURY_ADDRESS`: Your treasury wallet
	 - `VRF_COORDINATOR`: 0x41034422FA37197F49965a383501229671542475
	 - `VRF_SUBSCRIPTION_ID`: Create/fund in Chainlink VRF UI for Arbitrum Sepolia
	 - `GAS_LANE`: 0x114f3da0a805b8a67d6a7a05154f14afd91811821b38e09e03ade28a24ac2166

2) (Optional) Deploy TestUSDC and mint:
```bash
forge script script/TestUSDC.s.sol:TestUSDCScript \
	--rpc-url $RPC_URL \
	--private-key $PRIVATE_KEY \
	--broadcast
```
Record the address and set `USDC_ADDRESS` in `.env`. Use `mint(address,uint256)` from the owner to fund test accounts.

3) Create and fund a VRF subscription for chain 421614:
	 - Add your deployer address as a consumer if required by the coordinator
	 - Ensure enough LINK/native fee as per Chainlink docs for testnet

4) Deploy QuantumLottery:
```bash
forge script script/Deploy.s.sol:DeployScript \
	--rpc-url $RPC_URL \
	--private-key $PRIVATE_KEY \
	--broadcast
```
The address is printed in the broadcast artifact under `broadcast/Deploy.s.sol/421614/run-*.json`.

5) Verify (optional): set your Etherscan API key then run with `--verify`.

Troubleshooting:
- If VRF requests fail, ensure subscription is funded and the consumer (lottery address) is authorized.
- If `processDrawChunk` reverts for gas, reduce `iterations` and call repeatedly until done.

## Frontend integration
- ABI: compile artifacts under `out/`
- Core calls: `buyTicket(ticketType)`, `requestRandomWinner(hourId)`, `processDrawChunk(hourId, iterations)`, `cleanupDrawChunk(hourId, iterations)`, `claimRefund(hourId)`
- Views: `getPrizePot(hourId)`, `getWinner(hourId)`, `getDrawStatus(hourId)`, `getParticipantsCount(hourId)`, `lastEnteredHour(player)`
- Important: `processDrawChunk` should be called repeatedly until it returns `true`, then call `cleanupDrawChunk` until done

## Security notes
- CEI and `nonReentrant` on external state-changing calls where relevant
- Chainlink VRF request is wrapped in `try/catch`; reentrancy into the callback within the same tx is not possible
- Strict equality and timestamp comparisons are intentional for hour-based gating and duplicate prevention
- Libraries do storage-safe updates and return data for event emission in the base contract

## License

MIT
