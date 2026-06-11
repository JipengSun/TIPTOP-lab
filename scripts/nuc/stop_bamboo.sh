#!/bin/bash
# Stop Bamboo arm and Robotiq gripper server (works with or without tmux).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAMBOO_DIR="${BAMBOO_DIR:-$HOME/Desktop/bamboo}"

if command -v tmux >/dev/null 2>&1 && tmux has-session -t bamboo 2>/dev/null; then
  echo "Stopping tmux session 'bamboo'..."
  cd "$BAMBOO_DIR"
  bash RunBambooController stop || tmux kill-session -t bamboo 2>/dev/null || true
  exit 0
fi

echo "Stopping nohup bamboo processes..."
pkill -TERM -f 'bamboo_control_node' 2>/dev/null || true
pkill -TERM -f 'gripper_server.py' 2>/dev/null || true
sleep 2
pkill -KILL -f 'bamboo_control_node' 2>/dev/null || true
pkill -KILL -f 'gripper_server.py' 2>/dev/null || true

ss -tlnp 2>/dev/null | grep -E ':5555|:5559' || echo "Ports 5555 and 5559 are free."
