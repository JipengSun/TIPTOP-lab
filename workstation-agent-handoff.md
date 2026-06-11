# Workstation agent handoff — TiPToP / Bamboo status

**Generated:** 2026-06-10  
**From:** NUC agent (`pci-NUC15CRKU7`, `192.168.1.7`)  
**To:** Workstation agent (`192.168.1.6`)  
**Purpose:** Start TiPToP from the workstation after the NUC Bamboo stack is ready.

**Read these first:**

1. [`docs/nuc-tiptop-instructions.md`](docs/nuc-tiptop-instructions.md) — full NUC runbook
2. [`improvement.md`](improvement.md) — lab pitfalls (stack switching, gripper USB)
3. [TiPToP installation](https://tiptop-robot.readthedocs.io/en/latest/installation/) — upstream reference

---

## Executive summary

| Item | Status |
|------|--------|
| NUC → robot network | **OK** (`192.168.1.7` ↔ `192.168.1.11`) |
| NUC ↔ workstation network | **OK** (same `192.168.1.0/24` switch) |
| Bamboo installed on NUC | **OK** — `~/Desktop/bamboo`, conda env `bamboo` |
| `bamboo_control_node` built | **OK** — libfranka **0.19** (reused from DROID build) |
| Bamboo running | **OK** — `:5555` arm + `:5559` gripper listening |
| DROID Polymetis / zerorpc | **STOPPED** — ports **4242** / **50051** free |
| Realtime groups on NUC | **PENDING** — operator must run `setup_system.sh` + logout |
| Robotiq USB on NUC | **PENDING** — gripper still on workstation; no `/dev/ttyUSB*` on NUC |
| FCI | **Workstation action** — activate from Desk before Bamboo starts |

**Workstation action:** Complete pre-flight below, ask NUC operator to start Bamboo, then verify ZMQ connectivity and run `get-joint-positions`.

---

## Architecture (TiPToP mode)

```text
                    ┌─────────────┐
                    │   Switch    │
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
           │               │               │
    [Workstation]      [NUC]         [Robot C2]
    192.168.1.6        192.168.1.7     192.168.1.11
         │                  │               │
         │  Bamboo client   │               │
         └── ZMQ :5555 ────►│ bamboo_control_node
         └── ZMQ :5559 ────►│ gripper_server.py
                            └── libfranka ──►│  FCI
```

| Layer | Runs on | Port |
|-------|---------|------|
| TiPToP planner / client | Workstation | — |
| Bamboo arm control | NUC | ZMQ **5555** |
| Robotiq gripper server | NUC | ZMQ **5559** |

The workstation does **not** run libfranka or hold FCI during TiPToP. It connects to the NUC over ZMQ only.

---

## Critical rule: one stack at a time

| Stack | NUC ports | Use for |
|-------|-----------|---------|
| DROID / OpenPI | **4242**, **50051** | VR teleop, OpenPI rollout |
| **TiPToP / Bamboo** | **5555**, **5559** | TiPToP planning demos |

**Never run Polymetis and Bamboo together.** Only one process may hold FCI.

Before TiPToP:

- NUC: DROID stack stopped (already done as of this report)
- Workstation: do **not** run `RobotEnv(launch=True)` or OpenPI rollout

After TiPToP (return to DROID):

1. NUC: `bash ~/Desktop/bamboo/RunBambooController stop`
2. Workstation: restart Polymetis + zerorpc (see [Return to DROID](#return-to-droid) below)

---

## NUC setup progress (what the NUC agent completed)

| Step | Status | Notes |
|------|--------|-------|
| Clone `bamboo` → `~/Desktop/bamboo` | Done | |
| Conda env `bamboo` (Python 3.10) | Done | ZMQ, msgpack, boost, fmt via conda-forge |
| Link libfranka 0.19 | Done | From `~/Desktop/Franka/droid/.local/libfranka-0.19` |
| Build `bamboo_control_node` | Done | `~/Desktop/bamboo/controller/build/bamboo_control_node` |
| Install Python package | Done | `pip install -e bamboo[server]` |
| Helper scripts | Done | `~/Desktop/TIPTOP/scripts/nuc/` (on NUC) |
| Serial port groups (dialout) | **Operator** | `bash ~/Desktop/TIPTOP/scripts/nuc/fix_serial_permissions.sh` then `newgrp dialout` |
| Robotiq USB on NUC | **Operator** | Unplug from workstation, plug into NUC |
| Start Bamboo session | **Next** | After FCI + optional steps above |

NUC helper scripts (live on NUC at `~/Desktop/TIPTOP/scripts/nuc/`):

| Script | Purpose |
|--------|---------|
| `fix_serial_permissions.sh` | One-time sudo: add `dialout` + `tty` (no realtime group on this NUC) |
| `setup_bamboo.sh` | Reproducible Bamboo install (already run) |
| `env.sh` | `conda activate bamboo` + `LD_LIBRARY_PATH` |
| `start_bamboo.sh` | Detached tmux start (arm + gripper) |

---

## Workstation config

`tiptop/config/tiptop.yml` on this workstation is already set:

```yaml
robot:
  type: fr3_robotiq
  host: "192.168.1.7"
  port: 5555
  gripper_port: 5559
```

TiPToP GPU stack installed at `~/Desktop/TIPTOP` (`pixi run tiptop-run -h` verified).

---

## Session start procedure

### Step 1 — Workstation pre-flight (Desk)

Do this in a browser on the **workstation only** (`https://192.168.1.11/desk/`):

1. **Unlock brakes**
2. Mode → **Execution**
3. **Activate FCI**
4. Watchman: disable SLP-C / SLS-C rules that block FCI

Do **not** open Desk on the NUC during Bamboo.

### Step 2 — Physical: Robotiq USB (for grasping)

For full TiPToP (arm + gripper), move the Robotiq RS485-USB adapter from the **workstation** to the **NUC**.

- Arm-only motion works without this; `gripper-open` / `gripper-close` will fail until USB is on the NUC.
- NUC operator checks: `ls -la /dev/ttyUSB* /dev/ttyACM*`

### Step 3 — NUC operator starts Bamboo

On the **NUC** (after FCI is active):

```bash
source ~/Desktop/TIPTOP/scripts/nuc/env.sh
bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh
```

Or equivalently:

```bash
cd ~/Desktop/bamboo
bash RunBambooController start \
  --robot_ip 192.168.1.11 \
  --control_port 5555 \
  --listen_ip 0.0.0.0 \
  --gripper_type robotiq \
  --gripper_device /dev/ttyUSB0 \
  --gripper_port 5559
```

Expected: ports **5555** and **5559** listening on `192.168.1.7`. Gripper cycles once at startup if USB is connected.

### Step 4 — Workstation connectivity check

```bash
ping -c 2 192.168.1.7
nc -zv 192.168.1.7 5555
nc -zv 192.168.1.7 5559
```

All three must succeed before running TiPToP.

### Step 5 — Workstation smoke test

```bash
export TIPTOP_DIR=~/Desktop/TIPTOP
cd $TIPTOP_DIR/tiptop
pixi shell

get-joint-positions
gripper-open    # optional; needs Robotiq USB on NUC
gripper-close   # optional
```

**Success:** joint positions return without connection errors.

### Step 6 — Run TiPToP

From the same `pixi shell`, follow `tiptop/docs/getting-started.md` (perception servers, `GOOGLE_API_KEY`, workspace calibration, demo).

---

## Return to DROID

When TiPToP is finished:

1. **Workstation:** stop TiPToP scripts / release motion.
2. **NUC:** `bash ~/Desktop/bamboo/RunBambooController stop`
3. **Workstation (optional):** lock joints from Desk.
4. **Workstation:** restart DROID stack on NUC:

```bash
bash ~/Desktop/DROID/scripts/setup/openpi_start_polymetis.sh
bash ~/Desktop/DROID/scripts/setup/openpi_start_zerorpc.sh
```

Verify DROID:

```bash
nc -zv 192.168.1.7 4242
nc -zv 192.168.1.7 50051
```

---

## Safe shutdown order (TiPToP)

1. Workstation: stop TiPToP / release motion.
2. NUC: `bash RunBambooController stop` (prefer over `kill -9`).
3. Workstation: optionally lock joints from Desk.

---

## Troubleshooting (workstation view)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Connection refused` `:5555` | Bamboo not running on NUC | NUC: start Bamboo with `--listen_ip 0.0.0.0` |
| `Connection refused` `:5559` | Gripper server down or arm-only start | NUC: check `RunBambooController status`; plug USB into NUC |
| `FCI refused` on NUC | FCI not activated | Desk on **workstation** → Activate FCI; restart Bamboo |
| Arm works, gripper fails | USB still on workstation | Move Robotiq USB to NUC |
| Random disconnects | Polymetis still on NUC | NUC: stop DROID stack; confirm ports 4242/50051 free |
| `get-joint-positions` fails but `nc` OK | Wrong `tiptop.yml` host/port | Set `host: 192.168.1.7`, ports 5555/5559 |
| DROID broken after TiPToP | Bamboo still holding FCI | NUC: `RunBambooController stop`; restart Polymetis |

---

## Checklist for workstation agent

- [x] `tiptop/config/tiptop.yml`: `host: 192.168.1.7`, ports `5555` / `5559`
- [x] TiPToP GPU stack installed on workstation
- [x] NUC network reachable (`ping 192.168.1.7`)
- [x] DROID stack stopped on NUC (4242, 50051 free) — verified 2026-06-10
- [x] Desk on workstation: Execution + **Activate FCI** (user confirmed 2026-06-10)
- [x] NUC: Bamboo arm started (`:5555` listening; `kIgnore` realtime patch applied)
- [x] `nc -zv 192.168.1.7 5555` OK
- [x] Arm smoke test OK (joints + EE pose)
- [x] Robotiq USB on NUC + gripper `:5559` — `get-joint-positions`, `gripper-open`, `gripper-close` OK
- [ ] After session: NUC stops Bamboo before restarting DROID

---

## Related docs

| Doc | Path |
|-----|------|
| NUC TiPToP runbook | [`docs/nuc-tiptop-instructions.md`](docs/nuc-tiptop-instructions.md) |
| Lab notes | [`improvement.md`](improvement.md) |
| DROID workstation handoff (Polymetis mode) | [`~/Desktop/DROID/docs/agent-model-handoff.md`](/home/pci/Desktop/DROID/docs/agent-model-handoff.md) |
| DROID NUC runbook | [`~/Desktop/DROID/docs/nuc-agent-instructions.md`](/home/pci/Desktop/DROID/docs/nuc-agent-instructions.md) |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-10 | Initial handoff after NUC Bamboo install; Bamboo not yet started |
| 2026-06-10 | Workstation synced handoff; connectivity re-verified (5555/5559 refused — Bamboo not started) |
| 2026-06-10 | Bamboo arm running; arm smoke test passed; gripper pending (USB on workstation) |
