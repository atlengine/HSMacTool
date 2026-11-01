#!/bin/bash

CURR_BRANCH="$1"

if [[ -z "$CURR_BRANCH" ]]; then
	osascript -e 'display dialog "Cannot find the branch. Please, input the branch number" buttons {"OK"} default button "OK" with icon caution'
	exit 1
fi

PROJECT_PATH="$HOME/Team5/Hearthstone/$CURR_BRANCH/Pegasus/Client"
GAME_FOLDER="$HOME/Team5/Hearthstone/$CURR_BRANCH/Pegasus/Assets/Game"
DESIGN_DATA_PATH="$HOME/Team5/Hearthstone/$CURR_BRANCH/Pegasus/Assets/source/DesignData"
DBF_PATH="$PROJECT_PATH/UnimportedAssets/DBF"
TMPL_FOLDER=$DESIGN_DATA_PATH/DBFTemplates
DBFTEMPLATES_PATH="$PROJECT_PATH/UnimportedAssets/DBF"
CODE_FOLDER="$GAME_FOLDER/DBF-Classes"

if [[ ! -d "$PROJECT_PATH" ]]; then
	echo "Project path not found: $PROJECT_PATH" >&2
	exit 1
fi

if [[ ! -d "$DESIGN_DATA_PATH" ]]; then
	osascript -e 'display dialog "DesignData folder not found." buttons {"OK"} default button "OK" with icon caution'
	echo "DesignData folder not found: $DESIGN_DATA_PATH" >&2
	exit 1
fi

if ! command -v mono >/dev/null 2>&1; then
	osascript -e 'display dialog "mono command not found. Cannot import DBF." buttons {"OK"} default button "OK" with icon caution'
	echo "mono command not found." >&2
	exit 1
fi

echo "Importing DBF assets for branch: $CURR_BRANCH"

(
	cd "$DESIGN_DATA_PATH" || exit 1
	echo "************ Update DBF Personal"
    mono Tools/DBSync/DBSync.exe client-dbo DBI "$DBF_PATH" DBFTemplates

	echo "************ Update DBF Personal with code"
    mono $Tools/DBSync/DBSync.exe client-code "$DBF_PATH" "$CODE_FOLDER" DBFTemplates DBI --force --neverpause

	# echo "************ Create personal DB"
	# mono Tools/DBSync/DBSync.exe sqlite-create HI_SQLITE_ASSET
) || {
	osascript -e 'display dialog "ImportDBF failed. Check the terminal output for details." buttons {"OK"} default button "OK" with icon stop'
	exit 1
}