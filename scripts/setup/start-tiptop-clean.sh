#!/usr/bin/env bash
# Kill stale TiPToP processes on the workstation, start perception servers, launch tiptop-run.
#
# Usage: bash ~/Desktop/TIPTOP/scripts/setup/start-tiptop-clean.sh [options]
#
#   --execute-plan     run the plan on the real robot (default: plan only)
#   --record           record all four cameras over the plan-execution window
#   --record-session   record the two extra cameras for the whole session instead
#   --av-exposure US   Allied Vision exposure in microseconds (default 50000)
#   --av-gain DB       Allied Vision gain in dB
#   --record-fps N     requested FPS for the extra cameras (default 30)
#
# Recording covers all four cameras on the rig. TiPToP records the two it owns — hand ZED-M
# and external ZED 2i — into the run folder; a launcher adds the second tripod ZED
# (38924636) and the Allied Vision 1800 from inside the same process, because the ZED SDK
# allows one owner per camera and a separate recorder cannot open them.
#
# Either way the footage lands in ~/Desktop/multicam_recordings/<timestamp>_tiptop/.
#
#   --record          all four bounded by the same execution window. TiPToP's own two are
#                     hard-linked in from its run folder once it has written them.
#                     Needs --execute-plan: nothing is written on a plan-only run.
#   --record-session  the extra two run from launch to exit. Use it to capture perception and
#                     planning too, or to get footage out of a plan-only run.
#
# The two are mutually exclusive — one owner per camera. Either way the extra cameras take
# roughly 15 s to open, and the run waits for their first frames before going on.
set -eo pipefail

TIPTOP_DIR="${TIPTOP_DIR:-$HOME/Desktop/TIPTOP}"
# The recorder lives with its task; override if the MetaSpec 3-9 folder moves.
MULTICAM_DIR="${TIPTOP_MULTICAM_DIR:-/home/pci/Documents/Lekang/Project MetaSpec/threads/3_Application_mobile/9_Robot/code/multicam_record}"

EXECUTE_PLAN=false
RECORD=false
RECORD_SESSION=false
export TIPTOP_RECORD_MODE=""
export TIPTOP_AV_EXPOSURE=""
export TIPTOP_AV_GAIN=""
export TIPTOP_RECORD_FPS=""

usage() {
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute-plan)   EXECUTE_PLAN=true; shift ;;
    --record)         RECORD=true; shift ;;
    --record-session) RECORD_SESSION=true; shift ;;
    --av-exposure)    TIPTOP_AV_EXPOSURE="${2:?--av-exposure needs a value}"; shift 2 ;;
    --av-gain)        TIPTOP_AV_GAIN="${2:?--av-gain needs a value}"; shift 2 ;;
    --record-fps)     TIPTOP_RECORD_FPS="${2:?--record-fps needs a value}"; shift 2 ;;
    -h|--help)        usage ;;
    *) echo "ERROR: unknown option '$1' (try --help)"; exit 2 ;;
  esac
done

if $RECORD && $RECORD_SESSION; then
  echo "ERROR: --record and --record-session are mutually exclusive (one owner per camera)."
  exit 2
fi

if $RECORD || $RECORD_SESSION; then
  if [[ ! -f "$MULTICAM_DIR/run_tiptop_record.py" ]]; then
    echo "ERROR: recorder not found at $MULTICAM_DIR."
    echo "  Set TIPTOP_MULTICAM_DIR to the folder holding run_tiptop_record.py."
    exit 1
  fi
  # The extra cameras are driven by a subprocess: the Allied Vision SDK is in the `robot`
  # conda env, not in TiPToP's pixi env. Fail here rather than half-way through a demo.
  RECORDER_PY="${MULTICAM_PYTHON:-$HOME/anaconda3/envs/robot/bin/python}"
  if [[ ! -x "$RECORDER_PY" ]]; then
    echo "ERROR: no camera interpreter at $RECORDER_PY (needs pyzed and vmbpy)."
    echo "  Point MULTICAM_PYTHON at one, or install vmbpy — see ~/Desktop/robot_entries/vimbax_install.md."
    exit 1
  fi
  export MULTICAM_PYTHON="$RECORDER_PY"
  if $RECORD; then
    export TIPTOP_RECORD_MODE=execution
  else
    export TIPTOP_RECORD_MODE=session
  fi
  if $RECORD && ! $EXECUTE_PLAN; then
    echo "NOTE: --record only writes video during plan execution. Add --execute-plan,"
    echo "      or use --record-session to record the extra cameras regardless."
  fi
fi

log() { echo "==> $*"; }

export PATH="${HOME}/anaconda3/bin:${HOME}/.pixi/bin:${PATH}"
export LD_LIBRARY_PATH="/usr/local/zed/lib:${LD_LIBRARY_PATH:-}"
unset TIPTOP_VLM_PROVIDER TIPTOP_VLM_MODEL

log "Killing stale processes..."
pkill -TERM -f 'tiptop-run' 2>/dev/null || true
pkill -TERM -f 'run_tiptop_record.py' 2>/dev/null || true
pkill -TERM -f 'rerun --port=' 2>/dev/null || true
pkill -TERM -f 'm2t2_server.py' 2>/dev/null || true
pkill -TERM -f 'scripts/server.py' 2>/dev/null || true
sleep 3
pkill -KILL -f 'tiptop-run|run_tiptop_record.py|m2t2_server.py|scripts/server.py' 2>/dev/null || true
sleep 2

log "Starting M2T2 (:8123)..."
: > /tmp/m2t2_server.log
cd "$TIPTOP_DIR/M2T2"
nohup pixi run python m2t2_server.py >> /tmp/m2t2_server.log 2>&1 &
M2T2_PID=$!

log "Starting FoundationStereo (:1234)..."
: > /tmp/foundation_stereo_server.log
cd "$TIPTOP_DIR/FoundationStereo"
nohup pixi run python scripts/server.py >> /tmp/foundation_stereo_server.log 2>&1 &
FS_PID=$!

wait_for_port() {
  local port="$1" name="$2" logfile="$3" pid="$4" timeout="${5:-180}"
  for i in $(seq 1 "$timeout"); do
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      log "$name ready (:$port, ${i}s)"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: $name died. tail $logfile:"; tail -20 "$logfile"; return 1
    fi
    sleep 1
  done
  echo "ERROR: $name timeout. tail $logfile:"; tail -20 "$logfile"; return 1
}

wait_for_port 8123 "M2T2" /tmp/m2t2_server.log "$M2T2_PID" 180
wait_for_port 1234 "FoundationStereo" /tmp/foundation_stereo_server.log "$FS_PID" 300

NUC="${TIPTOP_NUC:-nuc}"
if ! nc -z -w 2 192.168.1.7 5555 2>/dev/null; then
  log "NUC Bamboo not responding — restarting on $NUC..."
  ssh -o BatchMode=yes "$NUC" 'bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh 2>/dev/null || true
    sleep 2
    bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh
    if ! ss -tlnp 2>/dev/null | grep -q ":5559 "; then
      bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh
    fi'
  sleep 2
fi
if ! nc -z -w 2 192.168.1.7 5555 2>/dev/null || ! nc -z -w 2 192.168.1.7 5559 2>/dev/null; then
  echo "ERROR: NUC Bamboo/gripper not up on :5555/:5559. Activate FCI on Desk, then:"
  echo "  ssh nuc 'bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh; bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh'"
  exit 1
fi
log "NUC Bamboo ready (:5555, :5559)"

log "Starting tiptop-run..."
cd "$TIPTOP_DIR/tiptop"

RUN_ARGS=()
$EXECUTE_PLAN || RUN_ARGS+=(--no-execute-plan)

if [[ -z "$TIPTOP_RECORD_MODE" ]]; then
  exec pixi run tiptop-run "${RUN_ARGS[@]}"
fi

# --enable-recording is TiPToP's own hand + external recorder; the launcher adds the other two.
RUN_ARGS+=(--enable-recording)
exec pixi run python "$MULTICAM_DIR/run_tiptop_record.py" "${RUN_ARGS[@]}"
