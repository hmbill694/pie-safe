#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colours for prefixed output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

prefix_output() {
  local label="$1"
  local colour="$2"
  while IFS= read -r line; do
    printf "${colour}[%s]${RESET} %s\n" "$label" "$line"
  done
}

cleanup() {
  echo ""
  echo "Stopping all processes..."
  # Kill the whole process group so any child processes are also cleaned up
  kill -- -$$ 2>/dev/null || true
}

trap cleanup SIGINT SIGTERM

# Detect file watcher (prefer watchexec, fall back to entr)
if command -v watchexec &>/dev/null; then
  WATCHER="watchexec"
elif command -v entr &>/dev/null; then
  WATCHER="entr"
else
  printf "${YELLOW}[warn]${RESET} No file watcher found — backend will not hot reload.\n"
  printf "${YELLOW}[warn]${RESET} Install one to enable backend reloading:\n"
  printf "${YELLOW}[warn]${RESET}   brew install watchexec   (recommended)\n"
  printf "${YELLOW}[warn]${RESET}   brew install entr\n"
  WATCHER="none"
fi

# Start the Mist backend (port 3000) with file watching if available
if [ "$WATCHER" = "watchexec" ]; then
  (
    cd "$REPO_ROOT/backend"
    watchexec \
      --restart \
      --watch src \
      --watch ../core/src \
      --exts gleam \
      -- gleam run 2>&1
  ) | prefix_output "backend" "$GREEN" &
elif [ "$WATCHER" = "entr" ]; then
  (
    cd "$REPO_ROOT/backend"
    find src ../core/src -name '*.gleam' | \
      entr -r sh -c 'gleam run' 2>&1
  ) | prefix_output "backend" "$GREEN" &
else
  (
    cd "$REPO_ROOT/backend"
    gleam run 2>&1
  ) | prefix_output "backend" "$GREEN" &
fi
BACKEND_PID=$!

# Give the backend a moment to start before lustre/dev starts its proxy
sleep 1

# Start the Lustre dev server with live reload (port 1234)
(
  cd "$REPO_ROOT/ui"
  gleam run -m lustre/dev start 2>&1
) | prefix_output "ui" "$CYAN" &
UI_PID=$!

echo ""
echo "  Backend  → http://localhost:3000  (hot reload: ${WATCHER})"
echo "  Frontend → http://localhost:1234  (live reload)"
echo ""
echo "Press Ctrl+C to stop both."
echo ""

# Wait for either process to exit
wait $BACKEND_PID $UI_PID
