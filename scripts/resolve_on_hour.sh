#!/usr/bin/env zsh
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -- "$here/.." && pwd)
cd "$repo_root"

if [[ -f .env ]]; then
	set -a; source .env; set +a
fi

if [[ -z "${LOTTERY:-}" ]]; then
	echo "LOTTERY not set in .env"; exit 1
fi

HOUR_ID=${HOUR_ID:-}
if [[ -z "$HOUR_ID" ]]; then
	# default to previous hour
	HOUR_ID=$(( $(date +%s) / 3600 - 1 ))
fi

echo "Resolving hour $HOUR_ID for lottery $LOTTERY"

forge script script/ResolveHour.s.sol:ResolveHour \
	--rpc-url "$RPC_URL" \
	--private-key "$PRIVATE_KEY" \
	--broadcast \
	-vvvv
