#!/bin/bash
# Start Bamboo arm (:5555) + Robotiq gripper server (:5559) on the NUC.
# Uses tmux when available; otherwise falls back to nohup (no tmux required).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

ROBOT_IP="${ROBOT_IP:-192.168.1.11}"
CONTROL_PORT="${CONTROL_PORT:-5555}"
LISTEN_IP="${LISTEN_IP:-0.0.0.0}"
GRIPPER_DEVICE="${GRIPPER_DEVICE:-/dev/ttyUSB0}"
GRIPPER_PORT="${GRIPPER_PORT:-5559}"
BAMBOO_BUILD="${BAMBOO_BUILD:-$BAMBOO_DIR/controller/build/bamboo_control_node}"

_port_listening() {
  local port="$1"
  ss -tlnp 2>/dev/null | grep -q ":${port} "
}

_bamboo_healthy() {
  _port_listening "$CONTROL_PORT" && _port_listening "$GRIPPER_PORT"
}

_stop_stale_session() {
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t bamboo 2>/dev/null; then
    echo "Removing stale tmux session 'bamboo'..."
    cd "$BAMBOO_DIR"
    bash RunBambooController stop 2>/dev/null || tmux kill-session -t bamboo 2>/dev/null || true
  fi
  pkill -TERM -f 'bamboo_control_node' 2>/dev/null || true
  pkill -TERM -f 'gripper_server.py' 2>/dev/null || true
  sleep 2
}

if _bamboo_healthy; then
  echo "Bamboo already running (:$CONTROL_PORT and :$GRIPPER_PORT listening)."
  exit 0
fi

if command -v tmux >/dev/null 2>&1 && tmux has-session -t bamboo 2>/dev/null; then
  echo "tmux session 'bamboo' exists but ports are not up — cleaning up..."
  _stop_stale_session
fi

# Headless when: BAMBOO_HEADLESS=1, or no TTY (SSH non-interactive), or no tmux.
# RunBambooController tries to attach a terminal after start and fails with
# "open terminal failed: not a terminal" over SSH — that aborts callers under set -e.
_use_tmux=false
if [[ "${BAMBOO_HEADLESS:-0}" != "1" ]] && [[ -t 0 ]] && command -v tmux >/dev/null 2>&1; then
  _use_tmux=true
fi

if [[ "$_use_tmux" == "true" ]]; then
  echo "Starting via RunBambooController (tmux)..."
  cd "$BAMBOO_DIR"
  # Attach failure is OK if ports come up — do not let set -e abort here.
  bash RunBambooController start \
    --robot_ip "$ROBOT_IP" \
    --control_port "$CONTROL_PORT" \
    --listen_ip "$LISTEN_IP" \
    --gripper_type robotiq \
    --gripper_device "$GRIPPER_DEVICE" \
    --gripper_port "$GRIPPER_PORT" || true

  for i in $(seq 1 20); do
    if _bamboo_healthy; then
      echo "Bamboo ready (tmux). Ports :$CONTROL_PORT and :$GRIPPER_PORT listening."
      exit 0
    fi
    sleep 1
  done
  echo "WARNING: RunBambooController started but ports not up after 20s — falling back to nohup."
  _stop_stale_session
fi

if [[ "${BAMBOO_HEADLESS:-0}" == "1" ]] || [[ ! -t 0 ]]; then
  echo "Starting Bamboo headless (nohup; SSH/non-TTY safe)..."
elif ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not found — starting with nohup (optional: sudo apt-get install -y tmux)"
fi

if [[ ! -x "$BAMBOO_BUILD" ]]; then
  echo "ERROR: $BAMBOO_BUILD not found. Build Bamboo on the NUC first."
  exit 1
fi

_stop_stale_session

: > /tmp/bamboo_control.log

echo "Starting bamboo_control_node on :$CONTROL_PORT ..."
nohup "$BAMBOO_BUILD" \
  -r "$ROBOT_IP" \
  -p "$CONTROL_PORT" \
  -l "$LISTEN_IP" \
  -g none \
  >> /tmp/bamboo_control.log 2>&1 &

for i in $(seq 1 15); do
  if _port_listening "$CONTROL_PORT"; then
    echo "bamboo_control_node listening on :$CONTROL_PORT (ready after ${i}s)"
    break
  fi
  if [[ "$i" -eq 15 ]]; then
    echo "ERROR: :$CONTROL_PORT not listening. See /tmp/bamboo_control.log"
    tail -20 /tmp/bamboo_control.log
    exit 1
  fi
  sleep 1
done

bash "$SCRIPT_DIR/start_gripper.sh"

echo ""
echo "Bamboo ready (nohup mode)."
echo "  Arm log:     /tmp/bamboo_control.log"
echo "  Gripper log: /tmp/bamboo_gripper.log"
echo "  Stop:        bash $SCRIPT_DIR/stop_bamboo.sh"
