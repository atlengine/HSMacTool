#!/bin/bash

set -u

pause_before_exit() {
	local exit_code=$?
	if [[ -t 0 ]]; then
		echo
		read -r -s -n 1 -p "Press any key to close..." || true
		echo
	fi
	exit "$exit_code"
}

trap pause_before_exit EXIT

usage() {
	echo "Usage: $0 [changelist-number]"
	echo "Copies current local CL files, relative to the active Perforce workspace root."
	echo "Destination: \$HOME/Team5/Archive/<YYMMDD_HHMM>_<first line of CL description>"
	echo "The timestamp uses the local archive creation time (24-hour clock)."
	echo "Unsafe folder-name characters are replaced with underscores."
	echo "Missing/unmapped files are reported and skipped. Existing archives are not overwritten."
	echo "Requires p4 and Python 3. Uses the script directory's Perforce configuration."
}

if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
	usage
	exit 0
fi

if [[ $# -gt 1 ]]; then
	usage >&2
	exit 1
fi

CL_NUMBER="${1:-}"
if [[ -z "$CL_NUMBER" ]]; then
	read -r -p "Perforce changelist number: " CL_NUMBER || exit 1
fi

if [[ ! "$CL_NUMBER" =~ ^[0-9]+$ || ! "$CL_NUMBER" =~ [1-9] ]]; then
	echo "A positive changelist number is required." >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)" || exit 1
cd "$SCRIPT_DIR" || exit 1

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

PYTHON_BIN="$(command -v python3)" || PYTHON_BIN=""
if [[ -z "$PYTHON_BIN" ]]; then
	for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3; do
		if [[ -x "$candidate" ]]; then
			PYTHON_BIN="$candidate"
			break
		fi
	done
fi

if [[ -z "$PYTHON_BIN" ]]; then
	echo "python3 command not found. Install Python 3 or add it to PATH." >&2
	exit 1
fi

"$PYTHON_BIN" - "$P4_BIN" "$CL_NUMBER" <<'PYTHON'
import io
import marshal
import os
from datetime import datetime
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def p4(*args, allow_unmapped=False):
    result = subprocess.run(
        [sys.argv[1], "-ztag", "-G", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    records = []
    stream = io.BytesIO(result.stdout)
    while stream.tell() < len(result.stdout):
        record = marshal.load(stream)
        records.append({
            os.fsdecode(key): os.fsdecode(value) if isinstance(value, bytes) else value
            for key, value in record.items()
        })
    stderr = os.fsdecode(result.stderr).strip()
    errors = [record for record in records if record.get("code") == "error"]
    # EV_EMPTY is used when a depot path is outside the current client view.
    unmapped = allow_unmapped and errors and all(
        int(record.get("generic", 0)) == 17 for record in errors
    )
    if (result.returncode or errors) and not unmapped:
        detail = "\n".join(record.get("data", str(record)).strip() for record in errors)
        raise RuntimeError(f"p4 {' '.join(args)} failed: {detail or stderr or 'no error details'}")
    if stderr:
        print(stderr, file=sys.stderr)
    if unmapped:
        for record in errors:
            print(f"Skip: {record.get('data', '').strip()}", file=sys.stderr)
    return [record for record in records if record.get("code") == "stat"]


def archive():
    changes = p4("describe", "-s", sys.argv[2])
    if len(changes) != 1 or "desc" not in changes[0]:
        raise RuntimeError("Perforce did not return a changelist description.")
    change = changes[0]
    lines = change["desc"].splitlines()
    name = re.sub(r'[/\\:\x00-\x1f\x7f]', "_", lines[0] if lines else "").strip()
    if name in ("", ".", ".."):
        raise RuntimeError("The first line of the CL description is not a valid folder name.")
    archive_root = Path.home() / "Team5" / "Archive"
    destination = archive_root / f"{datetime.now():%y%m%d_%H%M} {name}"
    if os.path.lexists(destination):
        raise RuntimeError(f"Archive already exists; nothing was overwritten: {destination}")

    info = p4("info")
    if len(info) != 1 or not info[0].get("clientRoot"):
        raise RuntimeError("No active Perforce workspace root was found.")
    root = Path(info[0]["clientRoot"])
    if not root.is_absolute() or not root.is_dir():
        raise RuntimeError(f"Invalid Perforce workspace root: {root}")
    resolved_root = root.resolve()

    depot_files = [
        value for key, value in change.items() if re.fullmatch(r"depotFile[0-9]+", key)
    ]
    if not depot_files:
        raise RuntimeError("This changelist contains no files.")

    files = {}
    skipped = 0
    for depot_file in depot_files:
        mappings = p4("where", depot_file, allow_unmapped=True)
        mapped = [
            record for record in mappings
            if "unmap" not in record and not record.get("depotFile", "").startswith("-")
            and record.get("path")
        ]
        if not mapped:
            print(f"Skip (not mapped): {depot_file}", file=sys.stderr)
            skipped += 1
            continue
        for mapping in mapped:
            source = Path(mapping["path"])
            if not source.is_file():
                print(f"Skip (no local file): {source}", file=sys.stderr)
                skipped += 1
                continue
            try:
                source.resolve().relative_to(resolved_root)
                try:
                    relative = source.relative_to(root)
                except ValueError:
                    relative = (source.parent.resolve() / source.name).relative_to(resolved_root)
            except ValueError:
                raise RuntimeError(f"Local file is outside the workspace root: {source}") from None
            files[relative] = source

    if not files:
        raise RuntimeError("No local files to archive; no archive was created.")

    archive_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".archiveCL-", dir=archive_root) as temporary:
        staging = Path(temporary) / "files"
        staging.mkdir()
        for relative, source in files.items():
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        if os.path.lexists(destination):
            raise RuntimeError(f"Archive already exists: {destination}")
        staging.rename(destination)
    print(f"Archived CL {sys.argv[2]}: {len(files)} file(s), {skipped} skipped.")
    print(f"Archive: {destination}")


try:
    archive()
except (OSError, RuntimeError, ValueError) as error:
    print(f"Archive failed: {error}", file=sys.stderr)
    sys.exit(1)
PYTHON

exit "$?"
