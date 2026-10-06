# Agent handoff — TiPToP workstation migration to `robotman`

**Created:** 2026-07-09  
**From:** `pci-blenderman` (`10.50.206.40`, abandoned)  
**To:** `robotman` (`10.50.167.32`, `pci@10.50.167.32`)  
**Purpose:** Continue TiPToP lab work on the new GPU workstation with full context.

**Read this doc first** on the new machine before any TiPToP setup, GPU work, or robot sessions.

---

## Executive summary

| Item | Status |
|------|--------|
| New workstation | **`robotman`** — RTX PRO 6000 Blackwell, 125 GB RAM, Ubuntu 24.04, driver **580.159.03** |
| Old workstation | **`pci-blenderman`** — abandoned (Pro 6000 POST failed; 64 GB RAM) |
| Code rsync | **Done** — `~/Desktop/TIPTOP` (~9.6 GB) from `pci-blenderman` |
| Pixi envs | **Pending** — run `scripts/setup/bootstrap-new-workstation.sh` (needs `curl` first) |
| ZED SDK | **Not installed yet** on `robotman` — run `pixi run install-zed` in `tiptop/` |
| API keys | Copied in `tiptop/.env` (gitignored) — verify keys load |
| NUC / robot | **Unchanged** — Bamboo on `192.168.1.7`, FR3 on `192.168.1.11` |
| DROID on new machine | Already at `~/Desktop/DROID` and `~/Desktop/openpi` |

**The Pro 6000 works on `robotman`.** The old `pci-blenderman` GPU upgrade is obsolete — do not follow [`rtx-pro-6000-gpu-handoff.md`](rtx-pro-6000-gpu-handoff.md) on this machine except for historical context.

---

## Network map (updated)

| Machine | Hostname | IP (lab WiFi) | Role |
|---------|----------|---------------|------|
| **Workstation (NEW)** | `robotman` | `10.50.167.32` | GPU, ZED cameras, TiPToP, M2T2, FoundationStereo |
| NUC (Bamboo) | `pci-NUC15CRKU7` | `192.168.1.7` | Arm `:5555`, Robotiq gripper `:5559` |
| Franka FR3 | — | `192.168.1.11` | Robot (FCI via Desk on workstation) |
| Old workstation | `pci-blenderman` | `10.50.206.40` | **Abandoned** |

SSH to new workstation: `ssh pci@10.50.167.32`  
SSH to NUC (from `~/.ssh/config`): `ssh nuc` → `pci@192.168.1.7`

**Note:** Lab robot network (`192.168.1.x`) and office WiFi (`10.50.x.x`) are separate. The workstation must reach both: NUC/robot over Ethernet or routed LAN, cameras USB-local.

---

## What was migrated

### Transferred via rsync (from `pci-blenderman`)

```
~/Desktop/TIPTOP/
├── docs/                    # runbooks + this handoff
├── scripts/nuc/             # Bamboo helpers (also on NUC)
├── scripts/setup/           # bootstrap + NUC gripper setup
├── improvement.md           # agent pitfalls log
├── workstation-agent-handoff.md
├── tiptop/                  # lab fork code (JipengSun/tiptop-fr3-lab)
│   ├── .env                 # OPENAI_API_KEY, GOOGLE_API_KEY (gitignored)
│   └── tiptop/config/tiptop.yml
├── M2T2/                    # + weights/ (~435 MB)
└── FoundationStereo/        # + pretrained_models/ (~3.9 GB)
```

### Excluded (rebuild or skip)

| Path | Reason |
|------|--------|
| `**/.pixi/` | OS-specific conda envs (22.04 → 24.04); rebuild with `pixi install` |
| `tiptop_outputs/` | Run artifacts; optional re-sync if needed |
| `tiptop/debug_bbox/` | Local debug outputs |

### Not yet on new machine

- ZED SDK (`/usr/local/zed`) — install with `pixi run install-zed`
- Pixi binary — installed by bootstrap script
- `TIPTOP_DIR` in `~/.bashrc` — added by bootstrap script

---

## Uncommitted code on old machine (check before trusting `lab/main`)

The `tiptop/` checkout on `pci-blenderman` had **local modifications not pushed** to `JipengSun/tiptop-fr3-lab`:

| File | Changes |
|------|---------|
| `tiptop/motion_planning.py` | Motion planning tweaks |
| `tiptop/perception/cameras/zed_camera.py` | ZED camera handling (+186 lines) |
| `tiptop/perception/cameras/__init__.py` | Camera init |
| `tiptop/recording.py` | Recording / metadata |
| `tiptop/tiptop_run.py` | Run flow |

These **were rsync'd** to `robotman`. If you reset `tiptop/` from git, you will lose them. Consider committing/pushing from `robotman` when stable.

### TIPTOP-lab wrapper repo (uncommitted on old machine)

| File | Status |
|------|--------|
| `docs/rtx-pro-6000-gpu-handoff.md` | Was untracked — now on `robotman` |
| `docs/workstation-migration-handoff.md` | This file |
| `improvement.md` | Local edits |
| `workstation-agent-handoff.md` | Minor edits |

Remote: `https://github.com/JipengSun/TIPTOP-lab.git` (branch `main`).

---

## First-time setup on `robotman`

Run on the **new workstation** (bootstrap not auto-run — execute manually):

```bash
# 0. Install curl if missing (pixi installer needs it)
sudo apt-get update && sudo apt-get install -y curl

# 1. Verify migration landed
ls ~/Desktop/TIPTOP/tiptop/.env
ls ~/Desktop/TIPTOP/FoundationStereo/pretrained_models/

# 2. Bootstrap pixi envs + shell config (~30–60 min)
bash ~/Desktop/TIPTOP/scripts/setup/bootstrap-new-workstation.sh

# 3. ZED SDK (cameras must be plugged in for license)
cd ~/Desktop/TIPTOP/tiptop
pixi run install-zed

# 4. Reload shell
source ~/.bashrc

# 5. Smoke test
cd ~/Desktop/TIPTOP/tiptop && pixi shell
tiptop-run -h
get-joint-positions    # needs NUC Bamboo running + FCI active
```

### Lab config (`tiptop/config/tiptop.yml`)

Already configured for this lab — **no change needed** unless NUC IP changes:

```yaml
robot:
  type: fr3_robotiq
  host: "192.168.1.7"
  port: 5555
  gripper_port: 5559

cameras:
  hand:
    serial: "10163006"
    type: zed
  external:
    serial: "38845842"
    type: zed

perception:
  vlm:
    provider: gemini
    model: gemini-robotics-er-1.6-preview
```

VLM keys in `tiptop/.env` (sourced from `~/.bashrc` after bootstrap).

---

## Running TiPToP (session checklist)

Full copy-paste runbook: [`tiptop-experiment-runbook.md`](tiptop-experiment-runbook.md)

**Quick order every session:**

1. **Desk** on workstation (`https://192.168.1.11/desk/`) — unlock, Execution, Activate FCI
2. **NUC** — stop DROID, start Bamboo:
   ```bash
   ssh nuc 'bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh; bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh'
   ```
3. **Workstation** — stop old perception servers, start fresh:
   ```bash
   pkill -f m2t2_server.py; pkill -f 'scripts/server.py'
   cd ~/Desktop/TIPTOP/M2T2 && pixi run server &          # :8123
   cd ~/Desktop/TIPTOP/FoundationStereo && pixi run server &  # :1234
   ```
4. **TiPToP**:
   ```bash
   cd ~/Desktop/TIPTOP/tiptop && pixi shell
   tiptop-run
   ```

**Critical rule:** Only one FCI client — stop Polymetis/DROID before Bamboo. See [`nuc-tiptop-instructions.md`](nuc-tiptop-instructions.md).

---

## Architecture (unchanged)

```text
                    ┌─────────────┐
                    │   Switch    │
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
           │               │               │
    [robotman]          [NUC]         [Robot C2]
    10.50.167.32        192.168.1.7     192.168.1.11
    (was .1.6)              │               │
         │  Bamboo ZMQ      │               │
         └── :5555 ────────►│ bamboo_control_node
         └── :5559 ────────►│ gripper_server.py
                            └── libfranka ──► FCI
```

| Stack | Workstation env | NUC ports |
|-------|-----------------|-----------|
| DROID + OpenPI | `conda activate robot` | 4242, 50051 |
| **TiPToP** | `pixi shell` in `tiptop/` | **5555**, **5559** |

---

## Known pitfalls (from [`improvement.md`](../improvement.md))

| Issue | Fix |
|-------|-----|
| `go_to_q()` closed cached Bamboo client | Fixed — don't call `client.close()` mid-run |
| OpenAI bbox coords wrong | Use Structured Outputs + `gpt-4o-2024-08-06`; default VLM is **Gemini** |
| ZED numpy 2 conflict | Keep numpy 2.x + ZED SDK 5.0+ |
| Bamboo `start_bamboo.sh` silent exit | `env.sh` uses `set +u` around conda |
| Gripper `:5559` timeout | Robotiq USB must be on **NUC**, not workstation |
| cuRobo planning fails from capture pose | `calibrate-wrist-cam`, `go-to-home`, reduce clutter |
| External ZED optional | Set `cameras.external.serial: ""` to skip |

---

## DROID coexistence on `robotman`

`~/Desktop/DROID` and `~/Desktop/openpi` already exist. TiPToP and DROID share the same NUC/robot but **never simultaneously**:

- **TiPToP session:** NUC runs Bamboo (`:5555`/`:5559`); workstation uses `pixi shell`
- **DROID session:** NUC runs Polymetis (`:4242`/`:50051`); workstation uses `conda activate robot`

DROID handoff: `~/Desktop/DROID/docs/agent-model-handoff.md`

---

## Verification checklist for next agent

- [ ] `~/Desktop/TIPTOP` present with `tiptop/`, `M2T2/`, `FoundationStereo/`
- [ ] `tiptop/.env` exists and keys load (`echo $GOOGLE_API_KEY | head -c 8`)
- [ ] `bash scripts/setup/bootstrap-new-workstation.sh` completed without errors
- [ ] `pixi run tiptop-run -h` works
- [ ] ZED SDK at `/usr/local/zed` (if using wrist/external cameras)
- [ ] `nvidia-smi` shows RTX PRO 6000
- [ ] `ping 192.168.1.7` and `nc -zv 192.168.1.7 5555` (when Bamboo running)
- [ ] M2T2 server responds on `:8123`, FoundationStereo on `:1234`
- [ ] Wrist ZED serial `10163006` detected (if cameras plugged in)
- [ ] Run `pytest tests/test_bbox_utils` in `tiptop/` after env ready

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [`tiptop-experiment-runbook.md`](tiptop-experiment-runbook.md) | Session copy-paste commands |
| [`nuc-tiptop-instructions.md`](nuc-tiptop-instructions.md) | NUC Bamboo install/run |
| [`workstation-agent-handoff.md`](../workstation-agent-handoff.md) | Bamboo status (update workstation IP to `robotman`) |
| [`improvement.md`](../improvement.md) | Agent mistake log |
| [`rtx-pro-6000-gpu-handoff.md`](rtx-pro-6000-gpu-handoff.md) | **Historical** — old machine only |
| [TiPToP upstream docs](https://tiptop-robot.readthedocs.io/en/latest/installation/) | Reference |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-09 | Initial migration handoff; rsync from `pci-blenderman` to `robotman` (`10.50.167.32`) |
