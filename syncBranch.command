#!/bin/bash

set -u

if [[ $# -ne 1 || -z "${1:-}" || "$1" == "." || "$1" == ".." || "$1" == */* ]]; then
	echo "Usage: $0 <branch>" >&2
	exit 1
fi

CURR_BRANCH="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
TEAM5_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)" || exit 1
HEARTHSTONE_ROOT="$(cd "$TEAM5_ROOT/Hearthstone" && pwd -P)" || exit 1
BRANCH_PATH="$HEARTHSTONE_ROOT/$CURR_BRANCH"

if [[ ! -d "$BRANCH_PATH" ]]; then
	echo "Branch directory not found: $BRANCH_PATH" >&2
	exit 1
fi

BRANCH_PATH="$(cd "$BRANCH_PATH" && pwd -P)" || exit 1
if [[ "$BRANCH_PATH" != "$HEARTHSTONE_ROOT/"* ]]; then
	echo "Branch directory is outside Hearthstone root: $BRANCH_PATH" >&2
	exit 1
fi

P4_BIN="$(command -v p4)" || P4_BIN=""
if [[ -z "$P4_BIN" ]]; then
	for candidate in /opt/homebrew/bin/p4 /usr/local/bin/p4; do
		if [[ -x "$candidate" ]]; then
			P4_BIN="$candidate"
			break
		fi
	done
fi

if [[ -z "$P4_BIN" ]]; then
	echo "p4 command not found. Install the Perforce CLI or add it to PATH." >&2
	exit 1
fi

cd "$BRANCH_PATH" || exit 1
echo "Syncing branch: $CURR_BRANCH ($BRANCH_PATH)"
"$P4_BIN" sync ./...
SYNC_EXIT_CODE=$?

if [[ -t 0 ]]; then
	echo
	read -r -s -n 1 -p "Press any key to close..." || true
	echo
fi

exit "$SYNC_EXIT_CODE"
