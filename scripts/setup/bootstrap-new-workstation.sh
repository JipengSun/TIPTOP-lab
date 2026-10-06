#!/usr/bin/env bash
# Bootstrap TiPToP on a fresh workstation (run ON the new machine).
# Usage: bash ~/Desktop/TIPTOP/scripts/setup/bootstrap-new-workstation.sh
set -euo pipefail

TIPTOP_DIR="${TIPTOP_DIR:-$HOME/Desktop/TIPTOP}"
export TIPTOP_DIR

log() { echo "==> $*"; }

# --- pixi ---
if ! command -v pixi >/dev/null 2>&1; then
  log "Installing pixi"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://pixi.sh/install.sh | bash
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://pixi.sh/install.sh | bash
  else
    log "Installing curl (needed for pixi installer)"
    sudo apt-get update -qq && sudo apt-get install -y curl
    curl -fsSL https://pixi.sh/install.sh | bash
  fi
  export PATH="$HOME/.pixi/bin:$PATH"
fi

# --- shell env ---
if ! grep -q 'TIPTOP_DIR' "$HOME/.bashrc" 2>/dev/null; then
  log "Adding TIPTOP_DIR to ~/.bashrc"
  cat >>"$HOME/.bashrc" <<'EOF'

# TiPToP lab
export TIPTOP_DIR="$HOME/Desktop/TIPTOP"
if [ -f "$TIPTOP_DIR/tiptop/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$TIPTOP_DIR/tiptop/.env"
  set +a
fi
export LD_LIBRARY_PATH="/usr/local/zed/lib:${LD_LIBRARY_PATH:-}"
EOF
fi

# --- GPU check ---
log "GPU"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true

# --- TiPToP ---
log "pixi install: tiptop"
cd "$TIPTOP_DIR/tiptop"
pixi install
pixi run setup-planners

if [ ! -d /usr/local/zed ]; then
  log "ZED SDK not found — run: cd $TIPTOP_DIR/tiptop && pixi run install-zed"
  log "(Requires stereo ZED cameras connected for license step)"
else
  log "ZED SDK present at /usr/local/zed"
fi

# --- M2T2 ---
log "pixi install: M2T2"
cd "$TIPTOP_DIR/M2T2"
pixi install
if [ ! -f weights/m2t2.pth ]; then
  pixi run download-weights
else
  log "M2T2 weights already present"
fi
pixi run setup

# --- FoundationStereo ---
log "pixi install: FoundationStereo"
cd "$TIPTOP_DIR/FoundationStereo"
pixi install
if [ ! -d pretrained_models ] || [ -z "$(ls -A pretrained_models 2>/dev/null)" ]; then
  pixi run download-checkpoints
else
  log "FoundationStereo checkpoints already present"
fi
pixi run setup || log "FoundationStereo setup (flash-attn) may need manual retry"

# --- smoke test ---
log "TiPToP CLI"
cd "$TIPTOP_DIR/tiptop"
pixi run tiptop-run -h | head -5

log "Done. Next: read docs/workstation-migration-handoff.md"
