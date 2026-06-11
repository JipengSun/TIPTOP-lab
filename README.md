# TiPToP Lab — pci-blenderman + NUC Bamboo (FR3)

Lab workspace for running [TiPToP](https://github.com/tiptop-robot/tiptop) on a Franka FR3 with Bamboo arm control, OpenAI Vision perception, M2T2 grasping, and FoundationStereo depth.

**Workstation:** `pci-blenderman` (`192.168.1.6`)  
**NUC (Bamboo):** `192.168.1.7` — arm `:5555`, Robotiq gripper `:5559`  
**Robot:** Franka FR3 `192.168.1.11` (FCI via Desk on workstation)

Set `TIPTOP_DIR=~/Desktop/TIPTOP`. Clone upstream deps into this tree:

```bash
git clone https://github.com/tiptop-robot/tiptop.git
git clone https://github.com/williamshen-nz/M2T2.git
git clone https://github.com/williamshen-nz/FoundationStereo.git
```

Apply TiPToP code changes from **[JipengSun/tiptop-fr3-lab](https://github.com/JipengSun/tiptop-fr3-lab)** (`main` = `lab/openai-vision-bbox-fixes` locally), or use the `tiptop/` checkout in this workspace.

---

## What was done

### Workstation setup

- Installed TiPToP, M2T2, and FoundationStereo via **pixi** under `TIPTOP_DIR`.
- Configured `tiptop/tiptop/config/tiptop.yml` for this lab: `fr3_robotiq`, Bamboo host `192.168.1.7`, ZED hand cam `10163006`, external `38845842`.
- Documented clean-start experiment flow in [`docs/tiptop-experiment-runbook.md`](docs/tiptop-experiment-runbook.md).

### NUC Bamboo stack

- Built Bamboo on NUC (`~/Desktop/bamboo`, libfranka 0.19, conda env `bamboo`).
- Added helper scripts in [`scripts/nuc/`](scripts/nuc/): `start_bamboo.sh`, `stop_bamboo.sh`, `status_bamboo.sh`, `start_gripper.sh`, `env.sh`, `fix_serial_permissions.sh`.
- Patched Bamboo `control_node.cpp` for non-RT NUC: `franka::RealtimeConfig::kIgnore` (same idea as Polymetis `use_real_time=false`).
- Fixed **`start_bamboo.sh` silent failure**: `set -u` + `conda activate` triggered `deactivate-gcc_linux-64.sh: unbound variable`; scripts now use `set -eo pipefail` and `env.sh` wraps conda in `set +u`.

Full NUC guide: [`docs/nuc-tiptop-instructions.md`](docs/nuc-tiptop-instructions.md).

### TiPToP code changes (`tiptop/` branch `lab/openai-vision-bbox-fixes`)

| Area | Changes |
|------|---------|
| **OpenAI Vision** | New `openai_vision.py`, `vlm.py` router; config `perception.vlm.provider: openai`, model `gpt-4o`. Gemini path preserved. |
| **BBox pipeline** | New `bbox_utils.py`: pixel parsing, OpenAI→internal normalized conversion, SAM mask refinement, containment retry for pick-in-box tasks. |
| **VLM goals** | `vlm_common.sanitize_grounded_atoms()` drops invalid predicates; infers `holding(target)` for pick tasks. |
| **Recording** | Every run saves RGB, bbox viz, mask viz, depth colormap, scene 3D under run root + `perception/`. |
| **Rerun** | `rerun_utils.py` logs pinhole intrinsics + native `Boxes2D` aligned with `cam/rgb`. |
| **Prompts** | `detect_and_translate_openai.txt` — pixel `[xmin, ymin, xmax, ymax]`, pick/holding examples. |
| **Deps** | `openai>=1.0.0` in `pyproject.toml`. |

---

## Known bugs and limitations

### Bbox / VLM localization (partially fixed, still imperfect)

| Issue | Status | Notes |
|-------|--------|-------|
| GPT-4o returns **pixel** coords, old code treated them as 0–1000 normalized | **Fixed** | `parse_openai_box_2d`, `openai_box_to_gemini_normalized`, prompt asks for pixels |
| Coordinate order confusion (ymin/xmin swap) | **Fixed** | Explicit `[xmin, ymin, xmax, ymax]` in prompt + parser |
| JPEG vs PNG coordinate drift | **Fixed** | OpenAI requests use PNG to match saved `rgb.png` |
| Loose boxes after detection | **Mitigated** | `refine_bboxes_from_masks()` after SAM |
| Peach not inside box container | **Mitigated** | One retry with correction prompt |
| **GPT-4o still mis-localizes** on cluttered scenes | **Open** | Boxes can land on wrong object; grasp planning may fail (`No grasps within threshold`) |
| Invalid goal atoms (`on(fruit, box)` when `box` undetected) | **Fixed** | `sanitize_grounded_atoms` |
| Rerun / saved viz misalignment vs RGB | **Fixed** | Pinhole + `Boxes2D` in `rerun_utils` |
| Wrist cam calibration `10163006` | **Placeholder** | Copied from MIT template; run `calibrate-wrist-cam` for accurate 3D / Rerun alignment |

### Infrastructure

| Issue | Status | Notes |
|-------|--------|-------|
| Bamboo `Net Exception` / `BambooConnectionError` | Operational | FCI not active or second client (Polymetis/DROID) holds robot; reactivate FCI, restart Bamboo |
| `start_bamboo.sh` conda `unbound variable` | **Fixed** | Re-sync `scripts/nuc/*.sh` to NUC |
| ZED SDK 4.2 vs numpy 2 | Workaround | Keep numpy 2.x + ZED 5.0+, or use DROID env for ZED |
| Only one FCI client | Constraint | Stop Polymetis before Bamboo |

---

## Quick start

```bash
# NUC — after FCI active on Desk
bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh
bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh

# Workstation — perception servers (see runbook for stop-old-first)
cd ~/Desktop/TIPTOP/M2T2 && pixi run server          # :8123
cd ~/Desktop/TIPTOP/FoundationStereo && pixi run server  # :1234

export TIPTOP_DIR=~/Desktop/TIPTOP
export OPENAI_API_KEY=...   # never commit; use tiptop/.env (gitignored)
cd $TIPTOP_DIR/tiptop && pixi shell
tiptop-run --no-execute-plan
```

Outputs: `~/tiptop_outputs/eval/<timestamp>/` (rgb, bboxes, masks, depth, logs).

---

## Repository layout

```
TIPTOP/
├── README.md                 # this file
├── docs/                     # runbooks and NUC instructions
├── scripts/nuc/              # Bamboo start/stop on NUC
├── scripts/setup/            # one-shot setup helpers
├── improvement.md            # agent notes / pitfalls
├── workstation-agent-handoff.md
├── tiptop/                   # modified TiPToP (see branch lab/openai-vision-bbox-fixes)
├── M2T2/                     # upstream clone
└── FoundationStereo/         # upstream clone
```

---

## Related

- [TiPToP lab fork (OpenAI + bbox fixes)](https://github.com/JipengSun/tiptop-fr3-lab)
- [TiPToP upstream](https://github.com/tiptop-robot/tiptop)
- [M2T2](https://github.com/williamshen-nz/M2T2)
- [FoundationStereo](https://github.com/williamshen-nz/FoundationStereo)
