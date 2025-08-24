#!/usr/bin/env zsh
set -euo pipefail

# Simple wrapper to ensure .env is loaded and foundry sees RPC_URL
if [[ -f .env ]]; then
	set -a
	source .env
	set +a
fi

if [[ -z "${RPC_URL:-}" ]]; then
	echo "RPC_URL is not set. Put it in .env or export it."
	exit 1
fi

exec "$@"
