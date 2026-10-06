#!/bin/bash
# NUC: kill Polymetis/DROID FCI clients, then restart Bamboo + gripper cleanly.
# Safe pkill patterns only — never bare 'run_server' (matches SSH shells).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

echo "=== Stopping Polymetis / DROID FCI clients ==="
pkill -f 'scripts/server/run_server.py' 2>/dev/null || true
pkill -f 'polymetis/build/run_server' 2>/dev/null || true
pkill -f 'droid/franka/launch_gripper.sh' 2>/dev/null || true
pkill -f 'launch_gripper.py' 2>/dev/null || true
pkill -f 'launch_robot.py' 2>/dev/null || true
sleep 2

echo "=== Restarting Bamboo (headless / SSH-safe) ==="
bash "$SCRIPT_DIR/stop_bamboo.sh" || true
sleep 2
# Force a fresh start even if ports somehow linger
pkill -TERM -f 'bamboo_control_node' 2>/dev/null || true
pkill -TERM -f 'gripper_server.py' 2>/dev/null || true
sleep 2
# Avoid RunBambooController attach over SSH ("open terminal failed: not a terminal")
export BAMBOO_HEADLESS=1
bash "$SCRIPT_DIR/start_bamboo.sh"
sleep 2
# start_bamboo nohup path already calls start_gripper; call again is a no-op if healthy
bash "$SCRIPT_DIR/start_gripper.sh" || true
sleep 2

echo "=== Status ==="
ss -ltn | grep -E '5555|5559|4242|50051' || true
if ss -tlnp 2>/dev/null | grep -q ':5555 ' && ss -tlnp 2>/dev/null | grep -q ':5559 '; then
  echo "Bamboo fresh start OK (:5555 + :5559)."
  exit 0
fi
echo "ERROR: Bamboo ports not both up after restart."
exit 1
