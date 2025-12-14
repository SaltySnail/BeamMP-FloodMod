#!/bin/bash

# Helper utility to autozip and copy a mod to BeamMP's resource folder
# Usage: ./automod.sh <modPath> <beammpResourceClientPath> [zipName] [serverPath]
# Example: ./automod.sh ./Resources/Client/floodBeamMP ~/.local/share/BeamMP-Launcher/Resources
# Example: ./automod.sh ./Resources/Client/floodBeamMP ~/.local/share/BeamMP-Launcher/Resources customName
# Example: ./automod.sh ./Resources/Client/floodBeamMP ~/.local/share/BeamMP-Launcher/Resources floodBeamMP ./Resources/Server/Flood

if [ $# -lt 2 ]; then
    echo "Usage: ./automod.sh <modPath> <beammpResourceClientPath> [zipName] [serverPath]" >&2
    exit 1
fi

MOD_PATH="${1%/}"
BEAMMP_RESOURCE_CLIENT_PATH="${2%/}"

# Check if the mod path exists
if [ ! -d "$MOD_PATH" ]; then
    echo "Mod path does not exist: $MOD_PATH" >&2
    exit 1
fi

# Use custom name if provided, otherwise use folder name
if [ $# -ge 3 ] && [ -n "$3" ]; then
    MOD_NAME="$3"
else
    MOD_NAME=$(basename "$MOD_PATH")
fi

# Optional server path
SERVER_PATH=""
if [ $# -ge 4 ]; then
    SERVER_PATH="${4%/}"
    if [ ! -d "$SERVER_PATH" ]; then
        echo "Warning: Server path does not exist: $SERVER_PATH" >&2
        echo "Server files will not be copied." >&2
        SERVER_PATH=""
    fi
fi

# Check if the BeamMP resource client path exists
if [ ! -d "$BEAMMP_RESOURCE_CLIENT_PATH" ]; then
    echo "BeamMP resource client path does not exist: $BEAMMP_RESOURCE_CLIENT_PATH" >&2
    exit 1
fi

update_mod() {
    echo "Updating mod..."
    
    # Create absolute path for zip file
    local zip_file
    if [[ "$MOD_PATH" = /* ]]; then
        zip_file="$MOD_PATH.zip"
    else
        zip_file="$(pwd)/$MOD_PATH.zip"
    fi
    
    if [ -f "$zip_file" ]; then
        rm "$zip_file"
    fi
    
    # Zip the contents directly (without parent folder)
    if command -v zip &> /dev/null; then
        (cd "$MOD_PATH" && zip -r -q "$zip_file" .)
    else
        # Use tar.gz as fallback
        zip_file="${zip_file%.zip}.tar.gz"
        tar -czf "$zip_file" -C "$MOD_PATH" . 2>/dev/null
        echo "Note: Using .tar.gz format (zip not available)"
    fi
    
    # Delete the old archive in the BeamMP resource path
    local dest_file="$BEAMMP_RESOURCE_CLIENT_PATH/$MOD_NAME.zip"
    local dest_file_tar="$BEAMMP_RESOURCE_CLIENT_PATH/$MOD_NAME.tar.gz"
    [ -f "$dest_file" ] && rm "$dest_file"
    [ -f "$dest_file_tar" ] && rm "$dest_file_tar"
    
    # Copy the new archive to the BeamMP resource path
    if [ -f "$zip_file" ]; then
        cp "$zip_file" "$BEAMMP_RESOURCE_CLIENT_PATH/"
        echo "Successfully updated client mod: $MOD_NAME"
    else
        echo "Error: Failed to create archive" >&2
        return 1
    fi
    
    # Copy server files if server path is provided
    if [ -n "$SERVER_PATH" ]; then
        local server_dest="$BEAMMP_RESOURCE_CLIENT_PATH/../Server/Flood"
        
        # Create server directory if it doesn't exist
        if [ ! -d "$server_dest" ]; then
            mkdir -p "$server_dest"
            echo "Created server directory: $server_dest"
        fi
        
        # Copy all files from server path to destination
        cp -r "$SERVER_PATH"/* "$server_dest/"
        echo "Successfully updated server files"
    fi
}

# Calculate hash of directory to detect changes
get_dir_hash() {
    local hash=""
    hash=$(find "$MOD_PATH" -type f -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
    
    # Also hash server files if provided
    if [ -n "$SERVER_PATH" ]; then
        local server_hash=$(find "$SERVER_PATH" -type f -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
        hash="${hash}${server_hash}"
    fi
    
    echo "$hash"
}

echo "Watching $MOD_PATH for changes..."
if [ -n "$SERVER_PATH" ]; then
    echo "Also watching $SERVER_PATH for changes..."
fi
echo "Press Ctrl+C to stop"

LAST_HASH=$(get_dir_hash)

# Initial update
update_mod

# Poll for changes every 2 seconds
while true; do
    sleep 2
    CURRENT_HASH=$(get_dir_hash)
    
    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
        echo "Changes detected!"
        update_mod
        LAST_HASH="$CURRENT_HASH"
    fi
done
