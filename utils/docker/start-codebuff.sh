#!/bin/bash
set -e

# ANSI color codes - using simpler codes for better compatibility
GRAY="$(tput setaf 8 2>/dev/null || echo '\033[90m')"  # Fallback to 90m if tput not available
RESET="$(tput sgr0 2>/dev/null || echo '\033[0m')"
GREEN="$(tput setaf 2 2>/dev/null || echo '\033[32m')"
YELLOW="$(tput setaf 3 2>/dev/null || echo '\033[33m')"
RED="$(tput setaf 1 2>/dev/null || echo '\033[31m')"

# Add timestamp to logs
log() {
    echo "[HOST] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

debug() {
    if [ "${DEBUG}" = true ]; then
        echo "[HOST] [DEBUG] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
    fi
}

error() {
    echo "[HOST] [ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
    log "Cleaning up..."
    if [ "${DEBUG}" = true ]; then
        debug "Stopping container: $CONTAINER_ID"
        docker stop "$CONTAINER_ID" >/dev/null 2>&1 || true
        debug "Removing container: $CONTAINER_ID"
        docker rm "$CONTAINER_ID" >/dev/null 2>&1 || true
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Determine correct 'stat' syntax based on platform (BSD/macOS vs GNU/Linux)
if stat -c %Y / >/dev/null 2>&1; then
    # GNU stat (Linux)
    STAT_CMD="stat -c"
else
    # BSD stat (macOS, FreeBSD, etc.)
    STAT_CMD="stat -f"
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Build or rebuild the Docker image
log "Checking Docker image..."
if ! docker images codebuff --format "{{.ID}}" | grep -q .; then
    log "Building Docker image for the first time..."
    docker build -t codebuff "$SCRIPT_DIR" || { error "Failed to build Docker image"; exit 1; }
else
    # Always rebuild if any of the scripts have been modified
    DOCKERFILE_MTIME=$($STAT_CMD %m "$SCRIPT_DIR/Dockerfile")
    WRAPPER_MTIME=$($STAT_CMD %m "$SCRIPT_DIR/codebuff-wrapper.sh")
    ENTRYPOINT_MTIME=$($STAT_CMD %m "$SCRIPT_DIR/entrypoint.sh")
    BRIDGE_MTIME=$($STAT_CMD %m "$SCRIPT_DIR/message-bridge.sh")

    # Get the most recent modification time
    LATEST_MTIME=$DOCKERFILE_MTIME
    for t in $WRAPPER_MTIME $ENTRYPOINT_MTIME $BRIDGE_MTIME; do
        if [ $t -gt $LATEST_MTIME ]; then
            LATEST_MTIME=$t
        fi
    done

    debug "Latest modification time: $LATEST_MTIME"
    debug "Raw modification time: $($STAT_CMD %Sm "$SCRIPT_DIR/Dockerfile")"

    # Always rebuild for now - safer while we're actively developing
    log "Scripts may have been modified. Rebuilding image..."
    docker build -t codebuff "$SCRIPT_DIR" || { error "Failed to rebuild Docker image"; exit 1; }
fi

# ------------------------- Get Project Path ------------------------------------
DEFAULT_PATH="$(pwd)"
if [ -n "$1" ]; then
    SELECTED_PROJECT_PATH="$1"
else
    printf "Enter the project path (%s%s%s): " "${GRAY}" "${DEFAULT_PATH}" "${RESET}"
    read -r SELECTED_PROJECT_PATH
    SELECTED_PROJECT_PATH=${SELECTED_PROJECT_PATH:-$DEFAULT_PATH}
fi

# Convert to absolute path
SELECTED_PROJECT_PATH=$(cd "$SELECTED_PROJECT_PATH" && pwd)

# ------------------------- Get Host Base Directory -----------------------------
# Automatically determine host mount dir as parent of project dir
HOST_MOUNT_DIR=$(dirname "$SELECTED_PROJECT_PATH")
RELATIVE_PATH=$(basename "$SELECTED_PROJECT_PATH")

# Extract project name from path
PROJECT_NAME="$RELATIVE_PATH"

# Debug output
echo
debug "Host mount dir: $HOST_MOUNT_DIR"
debug "Selected path: $SELECTED_PROJECT_PATH"
debug "Resolved to: $RELATIVE_PATH"
debug "Project name: $PROJECT_NAME"
echo

# Create comm directory inside the project directory
debug "Setting up communication directory..."
COMM_DIR="$SELECTED_PROJECT_PATH/.codebuff/comm"
mkdir -p "$COMM_DIR"
touch "$COMM_DIR/messages.txt" "$COMM_DIR/responses.txt"
chmod 666 "$COMM_DIR/messages.txt" "$COMM_DIR/responses.txt"

# Start container in background
log "Starting container..."
CONTAINER_ID=$(docker run -d --privileged \
    -e "PROJECT_PATH=$RELATIVE_PATH" \
    -e "PROJECT_NAME=$PROJECT_NAME" \
    -e "DEBUG=${DEBUG:-false}" \
    -v "$HOME/.config/manicode:/workspace/.config/manicode" \
    -v "$HOST_MOUNT_DIR:/workspace" \
    codebuff)

echo "${GREEN}Started container with ID: $CONTAINER_ID${RESET}"
debug "Container mounts:"
docker inspect "$CONTAINER_ID" --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'

# Wait for container to be ready with better error handling
log "Checking container status..."
timeout=300
start_time=$(date +%s)
while true; do
    # Check if container is still running using full container ID
    if ! docker ps --no-trunc -q | grep -q "$CONTAINER_ID"; then
        error "Container stopped unexpectedly"
        log "Container logs:"
        docker logs "$CONTAINER_ID"
        echo
        log "Exit code:"
        docker inspect "$CONTAINER_ID" --format='{{.State.ExitCode}}'
        exit 1
    fi

    # Check for ready signal
    if [ -s "$COMM_DIR/responses.txt" ] && grep -q "CONTAINER READY" "$COMM_DIR/responses.txt"; then
        log "Container started successfully"
        # Clear responses.txt after container is ready
        echo > "$COMM_DIR/responses.txt"
        break
    fi

    # Check timeout
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt "$timeout" ]; then
        error "Timeout waiting for container to start"
        log "Container logs:"
        docker logs "$CONTAINER_ID"
        docker stop "$CONTAINER_ID"
        exit 1
    fi
    sleep 1
done

# Start message bridge
debug "Starting message bridge..."
exec "$SCRIPT_DIR/message-bridge.sh" "$SELECTED_PROJECT_PATH"
