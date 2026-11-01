#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM5_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HEARTHSTONE_ROOT="$TEAM5_ROOT/Hearthstone"
LAUNCHER_SCRIPT="$SCRIPT_DIR/launchUnityEditor.command"
IMPORT_DBF_SCRIPT="$SCRIPT_DIR/importDbf.command"
SYNC_SCRIPT="$SCRIPT_DIR/syncBranch.command"

if [[ ! -x "$LAUNCHER_SCRIPT" ]]; then
	echo "Launcher script not found or not executable: $LAUNCHER_SCRIPT" >&2
	exit 1
fi

if [[ ! -x "$IMPORT_DBF_SCRIPT" ]]; then
	echo "Import DBF script not found or not executable: $IMPORT_DBF_SCRIPT" >&2
	exit 1
fi

if [[ ! -x "$SYNC_SCRIPT" ]]; then
	echo "Sync script not found or not executable: $SYNC_SCRIPT" >&2
	exit 1
fi

if [[ ! -d "$HEARTHSTONE_ROOT" ]]; then
	echo "Hearthstone root not found: $HEARTHSTONE_ROOT" >&2
	exit 1
fi

create_wrapper() {
	local wrapper_prefix="$1"
	local target_script="$2"
	local branch_name="$3"
	local wrapper_name="${wrapper_prefix}_${branch_name//./_}.command"
	local wrapper_path="$HEARTHSTONE_ROOT/$wrapper_name"

	if [[ -e "$wrapper_path" ]]; then
		echo "Skip existing: $wrapper_name"
		return 0
	fi

	cat > "$wrapper_path" <<EOF
#!/bin/bash
exec "$target_script" "$branch_name"
EOF

	chmod +x "$wrapper_path"
	echo "Created: $wrapper_name"
}

find "$HEARTHSTONE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r branch_dir; do
	branch_name="$(basename "$branch_dir")"
	create_wrapper "launch" "$LAUNCHER_SCRIPT" "$branch_name"
	create_wrapper "sync" "$SYNC_SCRIPT" "$branch_name"
	# create_wrapper "impDbf" "$IMPORT_DBF_SCRIPT" "$branch_name" # Disabled until resolving import DBF issues
done
