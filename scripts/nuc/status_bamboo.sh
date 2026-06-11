#!/bin/bash
# Check Bamboo arm (:5555) and gripper (:5559) on the NUC.
set -euo pipefail

echo "=== Bamboo status ==="
if command -v tmux >/dev/null 2>&1 && tmux has-session -t bamboo 2>/dev/null; then
  echo "tmux session 'bamboo': running"
else
  echo "tmux session 'bamboo': not running"
fi

if pgrep -af bamboo_control_node >/dev/null 2>&1; then
  echo "bamboo_control_node: running"
  pgrep -af bamboo_control_node
else
  echo "bamboo_control_node: not running"
fi

if pgrep -af gripper_server.py >/dev/null 2>&1; then
  echo "gripper_server.py: running"
  pgrep -af gripper_server.py
else
  echo "gripper_server.py: not running"
fi

echo ""
echo "=== Listening ports ==="
ss -tlnp 2>/dev/null | grep -E ':5555|:5559' || echo "Neither :5555 nor :5559 is listening."
