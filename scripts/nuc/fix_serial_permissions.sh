#!/bin/bash
# One-time: allow pci user to access Robotiq USB on NUC (requires sudo + re-login or newgrp).
#
# This lab runs without PREEMPT_RT; Bamboo uses RealtimeConfig::kIgnore on the NUC.
# Only dialout (+ tty) are required here — not the realtime group.
set -euo pipefail

GROUPS=(dialout tty)
for g in "${GROUPS[@]}"; do
  if ! getent group "$g" >/dev/null; then
    echo "ERROR: group '$g' does not exist on this system"
    exit 1
  fi
done

echo "=== Add $USER to dialout, tty (serial port access) ==="
sudo usermod -aG dialout,tty "$USER"

echo ""
echo "Done. Either:"
echo "  1) Log out and back in on the NUC, then run: bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh"
echo "  2) Or in this SSH session: newgrp dialout   then run start_gripper.sh"
echo ""
echo "Note: realtime group/limits skipped — this NUC uses Bamboo kIgnore (no PREEMPT_RT)."
