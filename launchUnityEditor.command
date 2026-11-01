#!/bin/bash
CURR_BRANCH="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMPORT_DBF_SCRIPT="$SCRIPT_DIR/importDbf.command"

if [[ -z "$CURR_BRANCH" ]]; then
	osascript -e 'display dialog "Cannot find the branch. Please, input the branch number" buttons {"OK"} default button "OK" with icon caution'
	exit 1
fi

PROJECT_PATH="$HOME/Team5/Hearthstone/$CURR_BRANCH/Pegasus/Client"
VERSION_FILE="$PROJECT_PATH/ProjectSettings/ProjectVersion.txt"
UNITY_HUB_EDITOR_ROOT="/Applications/Unity/Hub/Editor"
UNITY_EXE=""
UNITY_VERSION=""

if [[ ! -d "$PROJECT_PATH" ]]; then
	echo "Project path not found: $PROJECT_PATH" >&2
	exit 1
fi

if [[ -f "$VERSION_FILE" ]]; then
	UNITY_VERSION="$(sed -n 's/^m_EditorVersion: //p' "$VERSION_FILE" | head -n 1)"
fi

if [[ -n "$UNITY_VERSION" && -x "$UNITY_HUB_EDITOR_ROOT/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity" ]]; then
	UNITY_EXE="$UNITY_HUB_EDITOR_ROOT/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity"
elif command -v unity >/dev/null 2>&1; then
	UNITY_EXE="$(command -v unity)"
else
	echo "Unity editor not found for project version: ${UNITY_VERSION:-unknown}" >&2
	exit 1
fi

nohup "$UNITY_EXE" -disable-assembly-updater --subProject --disable-perforce -projectPath "$PROJECT_PATH" -buildTarget osx >/dev/null 2>&1 &
exit 0
