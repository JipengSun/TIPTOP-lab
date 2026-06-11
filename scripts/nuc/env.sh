#!/bin/bash
# Source before running Bamboo on the NUC: source ~/Desktop/TIPTOP/scripts/nuc/env.sh
# Note: callers must not use `set -u` before sourcing — conda hooks touch unset vars.
BAMBOO_DIR="${BAMBOO_DIR:-$HOME/Desktop/bamboo}"
BAMBOO_ENV="${BAMBOO_ENV:-bamboo}"

if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [[ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/anaconda3/etc/profile.d/conda.sh"
fi

set +u
eval "$(conda shell.bash hook)"
conda activate "$BAMBOO_ENV"
set -u 2>/dev/null || true

export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$BAMBOO_DIR/install/lib:${LD_LIBRARY_PATH:-}"
if [[ -d /opt/openrobots/lib ]]; then
  export LD_LIBRARY_PATH="/opt/openrobots/lib:$LD_LIBRARY_PATH"
fi

export PKG_CONFIG_PATH="$CONDA_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
