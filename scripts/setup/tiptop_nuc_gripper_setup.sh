#!/bin/bash
# Run from the WORKSTATION in an interactive terminal (needs NUC sudo password once).
#
# Do NOT pipe into this script — run it directly so ssh -tt can prompt for sudo:
#   bash ~/Desktop/TIPTOP/scripts/setup/tiptop_nuc_gripper_setup.sh
set -euo pipefail

exec 1>&2

echo "=== TiPToP: NUC gripper permissions + start gripper server ==="
echo "You will be prompted for the NUC sudo password."
echo ""

# NOTE: No heredoc here — heredoc steals stdin and breaks ssh -t / sudo password prompt.
ssh -tt nuc 'bash ~/Desktop/TIPTOP/scripts/nuc/fix_serial_permissions.sh && sg dialout -c "bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh"'

echo ""
echo "=== Verify from workstation (waiting up to 15s for gripper) ==="
nc -zv 192.168.1.7 5555
for i in $(seq 1 15); do
  if nc -zv 192.168.1.7 5559 2>&1 | grep -q succeeded; then
    echo "gripper :5559 ready (${i}s)"
    break
  fi
  sleep 1
  if [[ $i -eq 15 ]]; then
    echo "WARNING: :5559 still not up — gripper may still be activating; retry: nc -zv 192.168.1.7 5559"
  fi
done
