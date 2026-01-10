#!/bin/sh
set -e

# Get PUID and PGID from environment, default to 1000
PUID=${PUID:-1000}
PGID=${PGID:-1000}

# Check if group with PGID exists
if ! getent group $PGID > /dev/null 2>&1; then
    # Create group with specified GID
    addgroup -g $PGID electrumx
    GROUP_NAME="electrumx"
else
    # Get group name by GID
    GROUP_NAME=$(getent group $PGID | cut -d: -f1)
fi

# Check if user with PUID exists
if ! getent passwd $PUID > /dev/null 2>&1; then
    # Create user with specified UID and add to group
    adduser -D -G $GROUP_NAME -u $PUID electrumx
    USER_NAME="electrumx"
else
    # Get username by UID
    USER_NAME=$(getent passwd $PUID | cut -d: -f1)
fi

# Change ownership of /app and /data directories
chown -R $USER_NAME:$GROUP_NAME /app
chown -R $USER_NAME:$GROUP_NAME /data

# Switch to the user and run ElectrumX server
exec su-exec $USER_NAME "$@"

