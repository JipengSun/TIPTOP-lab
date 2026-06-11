#!/bin/bash
# Start Robotiq gripper ZMQ server on NUC (port 5559). Arm must already be on :5555.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

GRIPPER_DEVICE="${GRIPPER_DEVICE:-/dev/ttyUSB0}"
GRIPPER_PORT="${GRIPPER_PORT:-5559}"

if [[ ! -e "$GRIPPER_DEVICE" ]]; then
  echo "ERROR: $GRIPPER_DEVICE not found. Is Robotiq USB plugged into the NUC?"
  ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true
  exit 1
fi

if [[ ! -r "$GRIPPER_DEVICE" || ! -w "$GRIPPER_DEVICE" ]]; then
  echo "ERROR: no read/write on $GRIPPER_DEVICE (need dialout group)."
  echo "Run: bash ~/Desktop/TIPTOP/scripts/nuc/fix_serial_permissions.sh"
  id
  exit 1
fi

pgrep -f 'gripper_server.py' | xargs -r kill 2>/dev/null || true
sleep 1

cd "$HOME/Desktop/bamboo/controller"
nohup python gripper_server.py \
  --gripper-port "$GRIPPER_DEVICE" \
  --zmq-port "$GRIPPER_PORT" \
  >> /tmp/bamboo_gripper.log 2>&1 &

# Robotiq activation can take 5–10s before ZMQ listens
for i in $(seq 1 15); do
  if ss -tlnp 2>/dev/null | grep -q ":$GRIPPER_PORT "; then
    echo "gripper_server listening on :$GRIPPER_PORT (ready after ${i}s)"
    grep -E "Gripper connected|listening on port" /tmp/bamboo_gripper.log | tail -2
    exit 0
  fi
  sleep 1
done

echo "gripper_server failed — :$GRIPPER_PORT not listening after 15s"
echo "See /tmp/bamboo_gripper.log:"
tail -15 /tmp/bamboo_gripper.log
exit 1
