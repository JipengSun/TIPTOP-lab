#!/usr/bin/env bash
# Fresh TiPToP reset from the workstation:
#   1) NUC: kill Polymetis + restart Bamboo/gripper
#   2) Fold joints into cuRobo soft limits if needed
#   3) Move to TiPToP cam/capture home (robot.q_capture == robot.q_home in lab config)
#
# One-liner:
#   bash ~/Desktop/TIPTOP/scripts/setup/tiptop-go-home-fresh.sh
set -eo pipefail

TIPTOP_DIR="${TIPTOP_DIR:-$HOME/Desktop/TIPTOP}"
NUC_HOST="${NUC_HOST:-nuc}"
TIME_DILATION="${TIME_DILATION:-0.3}"
export PATH="${HOME}/anaconda3/bin:${HOME}/.pixi/bin:${PATH}"
export CONDA_OVERRIDE_CUDA="${CONDA_OVERRIDE_CUDA:-12.0}"

log() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [--time-dilation-factor N]"
      echo "  Resets arm to TiPToP cam/capture home (q_capture)."
      echo "  Desk must already have brakes unlocked + FCI activated."
      exit 0
      ;;
    --time-dilation-factor)
      TIME_DILATION="${2:?}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

log "NUC fresh restart (stop Polymetis + Bamboo, start Bamboo)..."
ssh -o ConnectTimeout=10 -o BatchMode=yes "$NUC_HOST" \
  "bash ~/Desktop/TIPTOP/scripts/nuc/restart_bamboo_fresh.sh"

log "Waiting for Bamboo ZMQ from workstation..."
for i in $(seq 1 30); do
  if nc -z -w 1 192.168.1.7 5555 2>/dev/null && nc -z -w 1 192.168.1.7 5559 2>/dev/null; then
    log "Ports :5555/:5559 reachable (${i}s)"
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    echo "ERROR: cannot reach NUC Bamboo ports. Check Desk FCI + NUC logs."
    exit 1
  fi
  sleep 1
done

cd "$TIPTOP_DIR/tiptop"

log "Soft-limit recovery (if needed)..."
pixi run python - <<'PY'
import numpy as np
from tiptop.utils import get_bamboo_client

# cuRobo FR3/Robotiq soft position limits used by TiPToP motion planning
limits_min = np.array([-2.7437, -1.7837, -2.9007, -3.0421, -2.8065, 0.5445, -3.0159])
limits_max = np.array([ 2.7437,  1.7837,  2.9007, -0.1518,  2.8065, 4.5169,  3.0159])
# Lab hard-learned: J6 (index 5) above ~3.75 also causes start-state failures
limits_max[5] = min(limits_max[5], 3.70)
margin = 0.05

client = get_bamboo_client()
q = np.array(client.get_joint_positions(), dtype=float)
print("joints before:", np.round(q, 4).tolist())
q_safe = np.minimum(np.maximum(q, limits_min + margin), limits_max - margin)
if np.allclose(q, q_safe, atol=1e-3):
    print("joints already in soft-limit range — skip fold")
else:
    print("folding to:", np.round(q_safe, 4).tolist())
    n = 25
    confs = np.stack([(1 - i / n) * q + (i / n) * q_safe for i in range(1, n + 1)])
    vels = np.zeros_like(confs)
    durations = [0.2] * n
    result = client.execute_joint_impedance_path(
        joint_confs=confs, joint_vels=vels, durations=durations
    )
    if not result.get("success"):
        raise SystemExit(f"soft-limit fold failed: {result}")
    q2 = np.array(client.get_joint_positions(), dtype=float)
    print("joints after fold:", np.round(q2, 4).tolist())
PY

# Cam/capture home — same target as tiptop-run's pre-task move (robot.q_capture).
# go-home now matches q_capture in lab tiptop.yml; call go-to-capture explicitly.
log "go-to-capture / cam home (time_dilation_factor=${TIME_DILATION})..."
pixi run go-to-capture --time-dilation-factor "$TIME_DILATION"

log "Verify (expect ~ q_capture [-0.034, 0.090, 0.080, -1.319, -0.003, 1.253, 0.030]):"
pixi run get-joint-positions
log "Done — arm at TiPToP cam/capture home."
