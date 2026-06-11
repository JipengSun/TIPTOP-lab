# TiPToP experiment runbook (copy-paste)

Step-by-step commands to run a TiPToP perception + planning experiment on this lab.

**This runbook always assumes a clean start** — stop old processes before starting new ones.

| Machine | IP | Role |
|---------|-----|------|
| Workstation (`pci-blenderman`) | `192.168.1.6` | GPU, cameras, TiPToP, M2T2, FoundationStereo |
| NUC | `192.168.1.7` | Bamboo arm + Robotiq gripper |
| Franka FR3 | `192.168.1.11` | Robot (FCI) |

**Rule:** Only one FCI client at a time. Stop DROID/Polymetis before TiPToP. See also [`nuc-tiptop-instructions.md`](nuc-tiptop-instructions.md).

---

## Clean-start checklist

Run these in order every session:

1. **NUC** — stop DROID + old Bamboo → start Bamboo fresh  
2. **Workstation Desk** — unlock brakes → Execution → Activate FCI  
3. **Workstation** — stop old M2T2 + FoundationStereo → start both fresh  
4. **Workstation** — `tiptop-run`

---

## 0. One-time setup (if not done already)

On the **workstation**:

```bash
echo 'export TIPTOP_DIR=~/Desktop/TIPTOP' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/zed/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

OpenAI API key (gitignored `tiptop/.env` or shell):

```bash
# Option A: already in ~/.bashrc or tiptop/.env — skip
# Option B: export for this session only
export OPENAI_API_KEY='your-key-here'
```

Sync NUC helper scripts (run from **workstation** when scripts change):

```bash
scp ~/Desktop/TIPTOP/scripts/nuc/{env.sh,start_bamboo.sh,stop_bamboo.sh,status_bamboo.sh,start_gripper.sh,fix_serial_permissions.sh} \
  pci@192.168.1.7:~/Desktop/TIPTOP/scripts/nuc/
ssh pci@192.168.1.7 'chmod +x ~/Desktop/TIPTOP/scripts/nuc/*.sh'
```

---

## 1. NUC — clean start Bamboo

SSH to the NUC:

```bash
ssh pci@192.168.1.7
```

### 1a. Stop everything (DROID + old Bamboo)

```bash
# DROID / Polymetis
pkill -f "scripts/server/run_server.py" 2>/dev/null
pkill -9 franka_panda_cl 2>/dev/null
pkill -9 run_server 2>/dev/null
pkill -f launch_robot.py 2>/dev/null

# Old Bamboo (tmux + nohup)
bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh 2>/dev/null || true
cd ~/Desktop/bamboo && bash RunBambooController stop 2>/dev/null || true
tmux kill-session -t bamboo 2>/dev/null || true
pkill -f bamboo_control_node 2>/dev/null || true
pkill -f gripper_server.py 2>/dev/null || true

sleep 2
ss -tlnp | grep -E '4242|50051|5555|5559' || echo "ports clear"
```

### 1b. Start Bamboo + gripper

```bash
bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh
bash ~/Desktop/TIPTOP/scripts/nuc/status_bamboo.sh
```

Expected: **`:5555`** (arm) and **`:5559`** (gripper) listening.

If `start_bamboo.sh` is missing on the NUC, install tmux and use RunBambooController:

```bash
sudo apt-get install -y tmux
cd ~/Desktop/bamboo
bash RunBambooController start \
  --robot_ip 192.168.1.11 \
  --control_port 5555 \
  --listen_ip 0.0.0.0 \
  --gripper_type robotiq \
  --gripper_device /dev/ttyUSB0 \
  --gripper_port 5559
bash RunBambooController status
```

---

## 2. Workstation — robot preflight

On the **workstation** browser: open Desk → unlock brakes → **Execution** → **Activate FCI**.

Then in a terminal:

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
export LD_LIBRARY_PATH=/usr/local/zed/lib:$LD_LIBRARY_PATH
source ~/.bashrc

ping -c 2 192.168.1.7
nc -zv 192.168.1.7 5555
nc -zv 192.168.1.7 5559

cd $TIPTOP_DIR/tiptop
pixi shell

get-joint-positions
viz-gripper-cam
```

If `get-joint-positions` fails: Bamboo is not running or FCI is not activated.

---

## 3. Workstation — clean start perception servers

Stop any leftover servers **before** starting new ones (run once on the workstation):

```bash
pkill -f m2t2_server.py 2>/dev/null || true
pkill -f 'FoundationStereo.*server.py' 2>/dev/null || true
pkill -f 'scripts/server.py' 2>/dev/null || true
sleep 2
ss -tlnp | grep -E '8123|1234' || echo "perception ports clear"
```

### Terminal A — M2T2 (grasps, port 8123)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/M2T2
pixi run server
```

Wait for: `Application startup complete` and no `address already in use` error.

### Terminal B — FoundationStereo (depth, port 1234)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/FoundationStereo
pixi run server
```

Wait for: `Model loaded successfully` and `Application startup complete`.

### Verify both servers (Terminal C or same shell)

```bash
nc -zv 127.0.0.1 8123
nc -zv 127.0.0.1 1234
```

Both must report **succeeded** before running TiPToP.

---

## 4. Run the experiment (Terminal C on workstation)

### Planning only (recommended first — no robot motion after plan)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
export LD_LIBRARY_PATH=/usr/local/zed/lib:$LD_LIBRARY_PATH
source ~/.bashrc

cd $TIPTOP_DIR/tiptop
pixi shell

tiptop-run --no-execute-plan
```

When prompted, enter a task, for example:

```text
pick the peach from the box
```

Type `exit` to quit the loop.

### Full run (plan + execute on robot)

```bash
tiptop-run
```

### Custom output directory

```bash
tiptop-run --no-execute-plan --output-dir ~/tiptop_outputs
```

Default output location (when cwd is `$HOME`):

```text
~/tiptop_outputs/eval/<YYYY-MM-DD_HH-MM-SS>/
```

---

## 5. What gets saved each run

```text
~/tiptop_outputs/eval/<timestamp>/
  rgb.png
  bboxes_viz.png
  masks_viz.png
  tiptop_run.log
  metadata.json
  tiptop_plan.json          # if planning succeeded
  perception/
    rgb.png
    bboxes_viz.png
    masks_viz.png
    bboxes.json             # includes box_2d_pixels
    depth.png
    depth_colormap.png
    scene_3d.png
    pointcloud.ply
    grasps.pt
    cutamp_env.pkl
```

List the latest run:

```bash
ls -td ~/tiptop_outputs/eval/*/ | head -1
```

---

## 6. Review results offline

### Rerun viewer (perception + plan visualization)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/tiptop
pixi shell

viz-tiptop-run --run-dir ~/tiptop_outputs/eval/2026-06-10_17-59-51/
```

Replace the path with your run folder.

In Rerun: open **`cam/rgb`** and enable **`cam/bboxes`** for aligned 2D boxes.

### Open saved images directly

```bash
RUN=~/tiptop_outputs/eval/$(ls -t ~/tiptop_outputs/eval | head -1)
xdg-open $RUN/bboxes_viz.png
xdg-open $RUN/masks_viz.png
xdg-open $RUN/perception/scene_3d.png
```

---

## 7. Shutdown (clean end of session)

### Workstation — stop TiPToP and perception servers

Ctrl+C in the `tiptop-run` terminal, then:

```bash
pkill -f m2t2_server.py 2>/dev/null || true
pkill -f 'FoundationStereo.*server.py' 2>/dev/null || true
pkill -f 'scripts/server.py' 2>/dev/null || true
ss -tlnp | grep -E '8123|1234' || echo "perception ports clear"
```

### NUC — stop Bamboo

```bash
ssh pci@192.168.1.7
bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh
ss -tlnp | grep -E '5555|5559' || echo "bamboo ports clear"
```

To return to DROID/OpenPI later, restart Polymetis on the NUC (see DROID docs).

---

## 8. Terminal layout (summary)

| Step | Terminal | Machine | Action |
|------|----------|---------|--------|
| 1 | SSH | NUC | `stop_bamboo.sh` → `start_bamboo.sh` |
| 2 | A | Workstation | stop old servers → `cd M2T2 && pixi run server` |
| 3 | B | Workstation | `cd FoundationStereo && pixi run server` |
| 4 | C | Workstation | `cd tiptop && pixi shell && tiptop-run --no-execute-plan` |

---

## 9. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `address already in use` `:8123` or `:1234` | Old server still running — run the **stop** block in section 3, then start again |
| `Session 'bamboo' already running` | Stale tmux — run section **1a** stop block, then **1b** start |
| `start_bamboo.sh` exits immediately; ports still down; `unbound variable` in conda | Old NUC scripts used `set -u` with conda — re-sync `scripts/nuc/*.sh` from workstation (section **1**), or manual start in **11E** |
| `tmux: command not found` | `sudo apt-get install -y tmux` on NUC, or use `start_bamboo.sh` (nohup fallback) |
| `BambooConnectionError` / `Net Exception` | Bamboo up but FCI lost on robot | Reactivate FCI in Desk; restart Bamboo on NUC (section 11E) |
| `Connection refused` `:5559` | Gripper server down; check Robotiq USB on NUC |
| `get-joint-positions` timeout | FCI not activated in Desk |
| ZED camera won't open | `export LD_LIBRARY_PATH=/usr/local/zed/lib:$LD_LIBRARY_PATH` |
| `OPENAI_API_KEY is not set` | `source ~/.bashrc` or set key in `tiptop/.env` |
| Bboxes look wrong | Check `perception/bboxes.json` → `box_2d_pixels`; re-run after code updates |
| `pixi run serve` not found | Use **`pixi run server`** (not `serve`) |
| Exits right after `Moving robot to capture` | Program stopped before task prompt — see **section 11** |

---

## 10. Full session copy-paste (clean start)

### NUC (SSH)

```bash
ssh pci@192.168.1.7

pkill -f "scripts/server/run_server.py" 2>/dev/null
pkill -9 franka_panda_cl 2>/dev/null
pkill -f launch_robot.py 2>/dev/null
bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh 2>/dev/null || true
tmux kill-session -t bamboo 2>/dev/null || true
pkill -f bamboo_control_node 2>/dev/null || true
pkill -f gripper_server.py 2>/dev/null || true
sleep 2

bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh
bash ~/Desktop/TIPTOP/scripts/nuc/status_bamboo.sh
```

### Workstation — stop old perception servers (once)

```bash
pkill -f m2t2_server.py 2>/dev/null || true
pkill -f 'FoundationStereo.*server.py' 2>/dev/null || true
pkill -f 'scripts/server.py' 2>/dev/null || true
sleep 2
```

### Workstation — Terminal A (M2T2)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/M2T2 && pixi run server
```

### Workstation — Terminal B (FoundationStereo)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/FoundationStereo && pixi run server
```

### Workstation — Terminal C (TiPToP)

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
export LD_LIBRARY_PATH=/usr/local/zed/lib:$LD_LIBRARY_PATH
source ~/.bashrc

nc -zv 127.0.0.1 8123
nc -zv 127.0.0.1 1234

cd $TIPTOP_DIR/tiptop
pixi shell
tiptop-run --no-execute-plan
```

---

## 11. Exits after "Moving robot to capture" (no task prompt)

If the log shows capture motion starting then immediately `Tearing down cameras and robot` **without**:

```text
Enter task instruction ...
```

the run ended early. Common causes:

### A. Ctrl+C during capture motion

`go_to_capture` plans and moves the arm (can take 10–30s). **Wait** — do not interrupt unless the arm is stuck.

### B. Motion planning failed

Test capture motion alone:

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/tiptop
pixi shell

go-to-capture
```

If this errors, read the traceback. Often: arm in a bad pose — use Desk **Programming** mode to move it closer to a neutral configuration, then retry.

### C. Gripper failed (`:5559`)

After capture, TiPToP calls `open_gripper()`. Verify on NUC:

```bash
bash ~/Desktop/TIPTOP/scripts/nuc/status_bamboo.sh
nc -zv 192.168.1.7 5559
```

From workstation inside `pixi shell`:

```bash
gripper-open
```

### D. Re-run with full log

```bash
cd $TIPTOP_DIR/tiptop
pixi shell
tiptop-run --no-execute-plan 2>&1 | tee /tmp/tiptop_run_full.log
```

Check `/tmp/tiptop_run_full.log` for `MotionPlanningError`, `Failed to execute trajectory`, or `Interrupted`.

### E. `BambooConnectionError: Net Exception` on `go-to-capture`

TCP to `:5555` may work briefly, but the **NUC lost FCI** to the robot. The Bamboo process is often still listening but cannot read joint state.

**Workstation (Desk):** unlock brakes → Execution → **Activate FCI** (do not open Desk on the NUC).

**NUC — clean restart Bamboo:**

```bash
ssh pci@192.168.1.7

bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh 2>/dev/null || true
tmux kill-session -t bamboo 2>/dev/null || true
pkill -f bamboo_control_node 2>/dev/null || true
pkill -f gripper_server.py 2>/dev/null || true
sleep 2

bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh
bash ~/Desktop/TIPTOP/scripts/nuc/status_bamboo.sh
tail -30 /tmp/bamboo_control.log
```

**Workstation — verify:**

```bash
nc -zv 192.168.1.7 5555
nc -zv 192.168.1.7 5559

cd ~/Desktop/TIPTOP/tiptop && pixi shell
get-joint-positions
go-to-capture
```

If `start_bamboo.sh` prints nothing and ports stay down, check for conda errors (`unbound variable` in deactivate-gcc). Re-sync scripts from workstation or use **manual start** below.

**NUC — manual start (if script fails):**

```bash
set +u
source ~/Desktop/TIPTOP/scripts/nuc/env.sh

: > /tmp/bamboo_control.log
nohup ~/Desktop/bamboo/controller/build/bamboo_control_node \
  -r 192.168.1.11 -p 5555 -l 0.0.0.0 -g none \
  >> /tmp/bamboo_control.log 2>&1 &

sleep 3
ss -tlnp | grep 5555
tail -20 /tmp/bamboo_control.log

bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh
```

---

## Related docs

- [`nuc-tiptop-instructions.md`](nuc-tiptop-instructions.md) — NUC Bamboo install/start
- [`../improvement.md`](../improvement.md) — lab-specific notes and pitfalls
- [`../workstation-agent-handoff.md`](../workstation-agent-handoff.md) — network / NUC status
