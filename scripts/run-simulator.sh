#!/bin/bash
# Kills any stuck/sleeping Connect IQ simulator, relaunches it fresh,
# rebuilds the app, and pushes it in. Run this whenever the simulator
# shows the blue sleep/pause triangle and won't wake up on its own.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
DEVICE="fenix847mm"
DEV_KEY="$HOME/.garmin-connectiq/developer_key.der"

if [ ! -d "$SDK" ]; then
  echo -e "${RED}SDK not found at: $SDK${NC}"
  echo -e "${YELLOW}Edit SDK= in this script if you've installed a different SDK version.${NC}"
  exit 1
fi

export PATH="$SDK/bin:$PATH"

echo "Killing any running simulator..."
pkill -f "ConnectIQ.app/Contents/MacOS/simulator" 2>/dev/null || true
sleep 2

echo "Launching simulator..."
open "$SDK/bin/ConnectIQ.app"
sleep 6

echo "Building..."
cd "$PROJECT_DIR"
if ! monkeyc -d "$DEVICE" -f monkey.jungle -o bin/HomePower.prg -y "$DEV_KEY" -w; then
  echo -e "${RED}Build failed.${NC}"
  exit 1
fi
echo -e "${GREEN}Build succeeded.${NC}"

echo "Pushing app into simulator..."
# monkeydo stays attached to stream the app's console output rather than
# exiting once the push succeeds, so it's backgrounded here - this script
# is done once the push itself has gone through, not once the app quits.
LOG_FILE="$(mktemp)"
monkeydo bin/HomePower.prg "$DEVICE" > "$LOG_FILE" 2>&1 &
MONKEYDO_PID=$!
sleep 4

if ! kill -0 "$MONKEYDO_PID" 2>/dev/null; then
  echo -e "${RED}monkeydo exited early - push likely failed:${NC}"
  cat "$LOG_FILE"
  exit 1
fi

echo -e "${GREEN}Done - simulator running with the latest build.${NC}"
echo "(App console output streaming to monkeydo PID $MONKEYDO_PID, log: $LOG_FILE)"
