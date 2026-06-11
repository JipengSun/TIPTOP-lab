# NUC agent instructions: TiPToP / Bamboo controller

Instructions for AI agents (and operators) running **on the NUC** — the machine that runs the real-time Franka controller for **TiPToP** sessions.

**Read these first:**

1. `[improvement.md](../improvement.md)` — lab-specific pitfalls (TiPToP vs DROID, gripper USB, ZED)
2. `[workstation-agent-handoff.md](../workstation-agent-handoff.md)` — workstation ↔ NUC network status
3. `[/home/pci/Desktop/DROID/docs/nuc-agent-instructions.md](/home/pci/Desktop/DROID/docs/nuc-agent-instructions.md)` — shared lab network, Desk, FCI workflow
4. [TiPToP installation — Bamboo section](https://tiptop-robot.readthedocs.io/en/latest/installation/) — upstream reference

**Last updated:** 2026-06-10

---

## Your role on the NUC (TiPToP mode)

For **TiPToP**, the NUC runs **Bamboo** (not Polymetis/DROID). The GPU workstation (`192.168.1.6`) connects to Bamboo over the LAN.


| Layer                  | What runs on NUC                                  | Port         |
| ---------------------- | ------------------------------------------------- | ------------ |
| Bamboo arm control     | `bamboo_control_node` (via `RunBambooController`) | ZMQ **5555** |
| Robotiq gripper server | `gripper_server.py` (Robotiq only)                | ZMQ **5559** |


```text
                    ┌─────────────┐
                    │   Switch    │
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
           │               │               │
    [Workstation]      [NUC]         [Robot C2]
    192.168.1.6        192.168.1.7     192.168.1.11
         │                  │               │
         │  bamboo client   │               │
         └── ZMQ :5555 ────►│               │
         └── ZMQ :5559 ────►│ (gripper)     │
                            └── libfranka ──►│  FCI
```

Workstation TiPToP config (`tiptop/config/tiptop.yml`):

```yaml
robot:
  type: fr3_robotiq
  host: "192.168.1.7"
  port: 5555
  gripper_port: 5559
```

---

## Critical lab rule: one FCI client, one control stack


| Stack               | NUC services                         | When to use               |
| ------------------- | ------------------------------------ | ------------------------- |
| DROID / OpenPI π₀.5 | Polymetis `:50051` + zerorpc `:4242` | VR teleop, OpenPI rollout |
| **TiPToP**          | **Bamboo** `:5555` + gripper `:5559` | TiPToP planning demos     |


**Never run Polymetis and Bamboo at the same time.** Only one process may hold FCI.

### Before starting Bamboo (TiPToP session)

On the **NUC**, stop the DROID stack:

```bash
# Stop zerorpc (if running)
pkill -f "scripts/server/run_server.py" 2>/dev/null

# Stop Polymetis (if running)
pkill -9 franka_panda_cl 2>/dev/null
pkill -9 run_server 2>/dev/null
pkill -f launch_robot.py 2>/dev/null

# Confirm ports are free
ss -tlnp | grep -E '4242|50051|5555|5559' || echo "ports clear"
```

Coordinate with the workstation operator — they should not run `RobotEnv(launch=True)` or OpenPI rollout during TiPToP.

### After TiPToP session (return to DROID)

```bash
cd /home/pci/Desktop/bamboo   # or wherever bamboo is cloned
bash RunBambooController stop

# Workstation operator restarts Polymetis + zerorpc via DROID scripts:
#   bash ~/Desktop/DROID/scripts/setup/openpi_start_polymetis.sh
#   bash ~/Desktop/DROID/scripts/setup/openpi_start_zerorpc.sh
```

---

## Lab network (this site)

Same as DROID — **192.168.1.0/24**, not upstream DROID `172.16.0.x`.


| Device             | IP             | Role                      |
| ------------------ | -------------- | ------------------------- |
| Robot (C2)         | `192.168.1.11` | Franka FR3 control box    |
| NUC (this machine) | `192.168.1.7`  | Bamboo + FCI              |
| Workstation        | `192.168.1.6`  | Desk, cameras, TiPToP GPU |


**NUC interface:** NetworkManager profile `**Franka-LAN`**, address `192.168.1.7/24` (see DROID `nuc-agent-instructions.md` if not configured).

**Desk / FCI:** activated from the **workstation browser only** (`https://192.168.1.11/desk/`). Do not open Desk on the NUC while Bamboo is running.

Pre-flight on workstation (operator):

1. Unlock brakes → **Execution** → **Activate FCI**
2. Watchman: no SLP-C / SLS-C rules blocking FCI

 

## Step 1 — One-time Bamboo installation

**Expected time:** ~10–20 minutes  
**Repo location (suggested):** `/home/pci/Desktop/bamboo`

### Prerequisites

1. Ubuntu 20.04+ on NUC (this lab: Ubuntu 22.04)
2. Wired Ethernet to robot C2 via switch (`ping 192.168.1.11` must work)
3. [libfranka system requirements](https://github.com/frankarobotics/libfranka/tree/release-0.15.2?tab=readme-ov-file#1-system-requirements) satisfied
4. **libfranka version:** match FCI firmware on the FR3. This lab's Polymetis build used **libfranka 0.19** (FCI server v10). When `InstallBambooController` prompts, enter the compatible version from the [FCI compatibility table](https://frankarobotics.github.io/docs/compatibility.html).
5. **Robotiq gripper inertia** already set in Desk (done during DROID setup)
6. If libfranka ≥ 0.14.0: install Pinocchio per libfranka docs **before** running the install script

### Install

```bash
cd ~/Desktop
git clone https://github.com/chsahit/bamboo.git
cd bamboo
bash InstallBambooController
```

Notes:

- The script builds libfranka locally; it does not overwrite system installs.
- You may be prompted for sudo (groups, packages).
- If `dialout` / `tty` groups are added, **log out and log back in** (or `newgrp dialout`) before using the gripper USB.

### Serial port permissions (Robotiq USB) — required

```bash
bash ~/Desktop/TIPTOP/scripts/nuc/fix_serial_permissions.sh
```

Adds `dialout` + `tty` only. Then `newgrp dialout` or logout/login.

### Realtime permissions — skipped on this lab

This NUC does **not** use a PREEMPT_RT kernel (same as DROID `use_real_time=false`). Bamboo is built with `franka::RealtimeConfig::kIgnore` — do **not** require the `realtime` group or `/etc/security/limits.conf` RT entries unless you remove that patch.

---

## Step 2 — Lab-specific: Robotiq gripper USB

In this lab, the Robotiq RS485-USB adapter is normally on the **workstation** (`192.168.1.6`) for DROID/OpenPI.

**Bamboo expects the gripper on the same machine as the arm controller** (`/dev/ttyUSB0` or `/dev/ttyACM0` on the NUC). TiPToP's `BambooFrankaClient` uses one host (`192.168.1.7`) for both arm (`5555`) and gripper (`5559`).


| Option                         | What to do                                                                              |
| ------------------------------ | --------------------------------------------------------------------------------------- |
| **A (recommended for TiPToP)** | Plug Robotiq USB into the **NUC** for TiPToP sessions. Unplug from workstation first.   |
| **B (arm-only test)**          | Start Bamboo arm without gripper device; TiPToP motion may work but grasping will fail. |
| **C (DROID session)**          | Keep gripper USB on workstation; use Polymetis stack instead of Bamboo.                 |


Check device on NUC:

```bash
ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

---

## Step 3 — Start Bamboo (every TiPToP session)

Run on the **NUC** after Desk FCI is active on the workstation.

### Option A — recommended helper script (tmux optional)

Copy/sync `~/Desktop/TIPTOP/scripts/nuc/` to the NUC if needed, then:

```bash
bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh
bash ~/Desktop/TIPTOP/scripts/nuc/status_bamboo.sh
```

This uses `RunBambooController` when **tmux** is installed; otherwise starts arm + gripper with **nohup** (no tmux required).

Stop:

```bash
bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh
```

### Option B — RunBambooController (requires tmux)

```bash
sudo apt-get install -y tmux

cd /home/pci/Desktop/bamboo

bash RunBambooController start \
  --robot_ip 192.168.1.11 \
  --control_port 5555 \
  --listen_ip 0.0.0.0 \
  --gripper_type robotiq \
  --gripper_device /dev/ttyUSB0 \
  --gripper_port 5559
```

### Option C — manual nohup (no tmux, no helper script)

```bash
source ~/Desktop/TIPTOP/scripts/nuc/env.sh

nohup ~/Desktop/bamboo/controller/build/bamboo_control_node \
  -r 192.168.1.11 -p 5555 -l 0.0.0.0 -g none \
  >> /tmp/bamboo_control.log 2>&1 &

bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh
```

- `--listen_ip 0.0.0.0` allows the workstation (`192.168.1.6`) to connect.
- If gripper is on a different tty: set `GRIPPER_DEVICE=/dev/ttyACM0` before `start_gripper.sh`
- tmux session name (Option B only): `bamboo` — detach with **Ctrl+B**, then **D**

Other commands (Option B only):

```bash
bash RunBambooController status   # check ports
bash RunBambooController attach   # reattach to tmux
bash RunBambooController stop     # end session
```

---

## Step 4 — Verify from the NUC

### Local port check

```bash
ss -tlnp | grep -E '5555|5559'
# or
bash RunBambooController status
```

Expected: both **5555** (arm) and **5559** (gripper, Robotiq) listening.

### Bamboo smoke test (on NUC)

```{warning}
No collision checking. Clear the workspace and avoid joint limits.
```

```bash
conda activate bamboo

# Arm trajectory test
python bamboo/examples/joint_trajectory.py

# Gripper open/close (Robotiq)
python bamboo/examples/gripper.py
```

Gripper should cycle once at startup when `RunBambooController` starts.

---

## Step 5 — Verify from the workstation

The workstation operator runs these **after** Bamboo is up on the NUC.

### Connectivity

```bash
ping -c 2 192.168.1.7
nc -zv 192.168.1.7 5555
nc -zv 192.168.1.7 5559
```

### TiPToP client check

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/tiptop
pixi shell

get-joint-positions
gripper-open    # optional
gripper-close   # optional
```

All should succeed without connection errors.

---

## Safe shutdown order

1. Workstation: stop TiPToP scripts / release any motion.
2. NUC: `bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh`
3. Workstation: optionally lock joints from Desk.
4. If returning to DROID: workstation runs `openpi_session_reset.sh` then restarts Polymetis + zerorpc on NUC.

Prefer `RunBambooController stop` (tmux kill) over `kill -9` on `bamboo_control_node` so libfranka disconnects cleanly.

---

## Troubleshooting


| Symptom                                       | Likely cause                          | Fix                                                                                                                                        |
| --------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `FCI refused` / arm won't connect             | FCI not activated                     | Desk on **workstation** → Activate FCI; restart Bamboo                                                                                     |
| `tmux: command not found` | `RunBambooController` needs tmux | `sudo apt-get install -y tmux` **or** `bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh` (nohup fallback) |
| `start_bamboo.sh` silent exit; `_CONDA_PYTHON_SYSCONFIGDATA_NAME_USED: unbound variable` | `set -u` + conda activate on old scripts | Re-sync `scripts/nuc/*.sh` from workstation; or `set +u` before `source env.sh` — see runbook section **11E** |
| Gripper device not found                      | USB on workstation, not NUC           | Plug Robotiq USB into NUC (option A above)                                                                                                 |
| `libfranka: realtime scheduling` error        | Missing realtime group/limits         | Run `setup_system.sh` + logout; **or** patch `control_node.cpp` to `franka::RealtimeConfig::kIgnore` and rebuild (this lab, no PREEMPT_RT) |
| Arm works, gripper fails                      | Wrong tty or gripper server down      | Check `/dev/ttyUSB`*; `RunBambooController status`                                                                                         |
| `Address already in use` `:5555`              | Old Bamboo or Polymetis still running | Stop both stacks; confirm with `ss -tlnp`                                                                                                  |
| Second client / random disconnects            | Polymetis still holding FCI           | Kill Polymetis on NUC before starting Bamboo                                                                                               |
| Desk UI spam                                  | Desk open on NUC                      | Close NUC browser; use workstation only                                                                                                    |


---

## Checklist for NUC agent

- [ ] DROID Polymetis + zerorpc **stopped** (ports 4242, 50051 free)
- [ ] `ping 192.168.1.11` OK from NUC wired interface
- [ ] Workstation Desk: Execution + FCI activated
- [ ] Robotiq USB plugged into **NUC** (for full TiPToP grasping)
- [ ] `RunBambooController start --robot_ip 192.168.1.11 --listen_ip 0.0.0.0`
- [ ] Ports **5555** and **5559** listening
- [ ] `python bamboo/examples/joint_trajectory.py` passes on NUC
- [ ] Workstation: `nc -zv 192.168.1.7 5555` and `get-joint-positions` OK

---

## Related docs


| Doc                           | Path                                                                                                                                         |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Workstation TiPToP setup      | `[improvement.md](../improvement.md)`                                                                                                        |
| Workstation ↔ NUC handoff     | `[workstation-agent-handoff.md](../workstation-agent-handoff.md)`                                                                            |
| DROID NUC runbook (Polymetis) | `[/home/pci/Desktop/DROID/docs/nuc-agent-instructions.md](/home/pci/Desktop/DROID/docs/nuc-agent-instructions.md)`                           |
| DROID arm control skill       | `[/home/pci/Desktop/DROID/.cursor/skills/control-arm-via-nuc/SKILL.md](/home/pci/Desktop/DROID/.cursor/skills/control-arm-via-nuc/SKILL.md)` |
| TiPToP getting started        | `[/home/pci/Desktop/TIPTOP/tiptop/docs/getting-started.md](../tiptop/docs/getting-started.md)`                                               |


---

## Changelog


| Date       | Change                                                   |
| ---------- | -------------------------------------------------------- |
| 2026-06-10 | Initial NUC TiPToP/Bamboo runbook for pci-NUC15CRKU7 lab |


