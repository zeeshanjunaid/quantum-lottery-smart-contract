#!/usr/bin/env zsh
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -- "$here/.." && pwd)
cd "$repo_root"

# Load env
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

require() {
  local name=$1
  if [[ -z ${!name:-} ]]; then
    echo "Missing required env var: $name"; exit 1
  fi
}

require PRIVATE_KEY
require RPC_URL
require TREASURY_ADDRESS

# 1) Deploy TestUSDC if not provided
if [[ -z ${USDC_ADDRESS:-} ]]; then
  echo "Deploying TestUSDC..."
  USDC_ADDRESS=$(forge script script/TestUSDC.s.sol:DeployTestUSDC --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --silent | awk '/Deployed TestUSDC:/ {print $NF}')
  echo "USDC_ADDRESS=$USDC_ADDRESS" | tee -a .env
fi

# 2) Deploy Lottery
if [[ -z ${LOTTERY:-} ]]; then
  echo "Deploying QuantumLottery..."
  LOTTERY=$(forge script script/Deploy.s.sol:DeployScript --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --silent | awk '/Deployed to:/ {print $NF}')
  echo "LOTTERY=$LOTTERY" | tee -a .env
fi

echo "LOTTERY=$LOTTERY"

echo "Setting up VRF (create+fund+add consumer)..."
forge script script/SetupVRF.s.sol:SetupVRF --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast -vvvv

echo "Seeding participants via MultiJoin..."
: ${JOIN_COUNT:=10}
: ${QUANTUM_COUNT:=3}
forge script script/MultiJoin.s.sol:MultiJoin --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast -vvvv

echo "Request winner for previous hour"
HOUR_ID=$(( $(date +%s) / 3600 - 1 ))
LOTTERY=$LOTTERY forge script script/ResolveHour.s.sol:ResolveHour --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast -vvvv

echo "Wait for VRF to fulfill, then process and cleanup"
ITER=${ITER:-50}
LOTTERY=$LOTTERY HOUR_ID=$HOUR_ID ITER=$ITER forge script script/SmokeProcess.s.sol:SmokeProcess --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast -vvvv

echo "Done. Use ShowStats or IdentifyWinner to inspect results."
