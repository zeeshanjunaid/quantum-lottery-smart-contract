## Deployed addresses (Arbitrum Sepolia 421614)

- TestUSDC: 0x495c42Ea5e1F7d7Eddfb458184b44Fa78725faf9
- QuantumLottery (latest): 0x66d745ed8CB04DB9b1F0CF4720d73D7FbC284509

VRF v2 (subscription):
- Coordinator: 0x50d47e4142598E3411aA864e08a44284e471AC6f
- Key Hash (gas lane): 0x027f94ff1465b3525f9fc03e9ff7d6d2c0953482246dd6ae07570c45d6631414
- Subscription ID: 449

LINK (Arbitrum Sepolia):
- Token: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E

Treasury: 0x94cF685cc5D26828e2CA4c9C571249Fc9B1D16Be

Notes:
- Ensure the subscription has LINK and that the consumer is added (AddVRFConsumer.s.sol).
- Ticket prices assume 6 decimals USDC (1 USDC = 1_000_000). Current prices: Standard=10 USDC, Quantum=30 USDC.
