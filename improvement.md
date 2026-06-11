# Agent improvement notes — TiPToP lab setup

## 2026-06-10 — TiPToP GPU workstation install on pci-blenderman

- `TIPTOP_DIR=/home/pci/Desktop/TIPTOP`; repos: `tiptop/`, `M2T2/`, `FoundationStereo/`.
- pixi installed to `~/.pixi/bin`; add `TIPTOP_DIR` to `~/.bashrc`.
- Install order: `pixi install` → `pixi run setup-planners` → `pixi run install-zed` → M2T2/FoundationStereo `pixi run setup` + weight downloads.
- **ZED SDK 4.2 + numpy 2 conflict:** `install-zed` downgrades numpy to 1.26 for pyzed 4.2, which breaks scipy/sklearn (built for numpy 2 on Python 3.12). Fix: keep **numpy 2.x** (`pip install "numpy>=2.4" scipy scikit-learn`) and upgrade to **ZED SDK 5.0+** for TiPToP camera use. Until then, DROID `robot` env still handles ZED via `/usr/local/zed/get_python_api.py`.
- TiPToP CLI verified: `cd $TIPTOP_DIR/tiptop && pixi run tiptop-run -h`.
- `tiptop/config/tiptop.yml` pre-filled for this lab: `fr3_robotiq`, Bamboo host `192.168.1.7`, hand cam `10163006`, external `38845842`.

## Lab architecture — TiPToP vs DROID/OpenPI

| Stack | Arm control | Workstation env | NUC service |
|-------|-------------|-----------------|-------------|
| DROID + OpenPI π₀.5 | Polymetis + zerorpc `:4242` | `conda activate robot` | `launch_robot.py` + `run_server.py` |
| **TiPToP** | **Bamboo** `:5555` / gripper `:5559` | `pixi shell` in `tiptop/` | `RunBambooController` |

**Only one FCI client at a time.** Do not run Polymetis and Bamboo simultaneously on the NUC.

- DROID/OpenPI handoff: `/home/pci/Desktop/DROID/docs/agent-model-handoff.md`
- NUC status handoff: `workstation-agent-handoff.md`
- Arm control skill: `/home/pci/Desktop/DROID/.cursor/skills/control-arm-via-nuc/SKILL.md`

## NUC TiPToP runbook

- **`docs/nuc-tiptop-instructions.md`** — full NUC agent guide: stop Polymetis, install/start Bamboo, lab IPs, gripper USB caveat, verification checklist.

## Before first TiPToP demo

1. Install **Bamboo** on NUC — follow **`docs/nuc-tiptop-instructions.md`** (replaces Polymetis for TiPToP sessions).
2. Set **`OPENAI_API_KEY`** for VLM (default in `tiptop.yml`: `perception.vlm.provider: openai`, model `gpt-4o`). Gemini still works if you set `GOOGLE_API_KEY` and `provider: gemini`. **Never commit API keys** — export in shell only.
3. **Clean start** perception servers each session (stop old processes first):
   - `pkill -f m2t2_server.py; pkill -f 'scripts/server.py'` then
   - M2T2: `cd $TIPTOP_DIR/M2T2 && pixi run server` (port 8123)
   - FoundationStereo: `cd $TIPTOP_DIR/FoundationStereo && pixi run server` (port 1234)
   - Full steps: **`docs/tiptop-experiment-runbook.md`**
4. Run `tiptop-config` in `pixi shell` to confirm YAML.
5. Verify: `get-joint-positions`, `viz-gripper-cam`.

## 2026-06-10 — NUC Bamboo install complete (TiPToP handoff)

- NUC agent report: `workstation-agent-handoff.md` (TiPToP/Bamboo mode).
- Bamboo built on NUC (`~/Desktop/bamboo`, libfranka 0.19, conda `bamboo`). DROID stack **stopped** (4242/50051 free).
- Bamboo **not started** yet — `:5555`/`:5559` refused from workstation until NUC runs `start_bamboo.sh`.
- **Operator pending on NUC:** `fix_serial_permissions.sh` (dialout only — no `realtime` group on non-RT NUC); Robotiq USB on NUC.
- NUC helper scripts live on NUC at `~/Desktop/TIPTOP/scripts/nuc/` (not synced to workstation repo).
- **Bamboo realtime fix (NUC):** default libfranka `kEnforce` fails without `realtime` group. Patched `control_node.cpp` to `franka::RealtimeConfig::kIgnore` (same idea as Polymetis `use_real_time=false`). Rebuild: `conda activate bamboo && cd ~/Desktop/bamboo/controller/build && cmake --build .`
- **Start arm without tmux:** `nohup ~/Desktop/bamboo/controller/build/bamboo_control_node -r 192.168.1.11 -p 5555 -l 0.0.0.0 -g none >> /tmp/bamboo_control.log 2>&1 &` (after sourcing conda + `env.sh` LD_LIBRARY_PATH)
- **`start_bamboo.sh` silent failure (2026-06-11):** `set -u` + `conda activate` triggered `deactivate-gcc_linux-64.sh: _CONDA_PYTHON_SYSCONFIGDATA_NAME_USED: unbound variable` — script exited before starting processes. Fix: `env.sh` wraps conda in `set +u`; NUC scripts use `set -eo pipefail` (no `-u`). Sync `scripts/nuc/*.sh` to NUC after pull.
- **Arm-only smoke test** (gripper USB still on workstation): `BambooFrankaClient(..., enable_gripper=False)` — `get-joint-positions` CLI times out on gripper `:5559` until Robotiq USB is on NUC.
- **`tiptop_nuc_gripper_setup.sh` must not use ssh heredoc** — heredoc steals stdin so `sudo` cannot prompt (`Pseudo-terminal will not be allocated`). Use `ssh -tt nuc 'remote command'` instead.

## 2026-06-10 — OpenAI Vision replaces Gemini (no Google API key)

- Added `tiptop/perception/openai_vision.py` + `vlm.py` router; `perception_wrapper.py` and `compute_gripper_mask.py` use `vlm.*` instead of hard-coded Gemini.
- Config: `tiptop/config/tiptop.yml` → `perception.vlm.provider: openai`, `model: gpt-4o`. Override via `TIPTOP_VLM_PROVIDER` / `TIPTOP_VLM_MODEL`.
- Dependency: `openai>=1.0.0` in `pyproject.toml`; `pixi run pip install openai` if needed.
- **OpenAI `json_object` mode requires a top-level object** — gripper mask prompt returns `{"bboxes": [...]}` not a bare JSON array.
- **Do not paste API keys in chat or commit them.** Workstation setup: key in gitignored `tiptop/.env`, sourced from `~/.bashrc`; `openai_vision.py` also auto-loads `tiptop/.env` for `pixi run`.
- Gemini path preserved for users with `GOOGLE_API_KEY` — set `perception.vlm.provider: gemini`.
- **OpenAI bbox coords:** GPT-4o returns pixel `[xmin, ymin, xmax, ymax]`, not 0-1000 normalized. Old code treated them as normalized + swapped order, shifting boxes to wrong objects (e.g. teddy instead of cardboard box). Fixed: `bbox_utils.openai_box_to_gemini_normalized()` + prompt requests pixel coords explicitly.

## 2026-06-10 — Per-run image saves + Rerun bbox alignment

- Added explicit save helpers in `recording.py`: `save_rgb_image`, `save_bbox_viz_image`, `save_mask_viz_image`, `save_depth_colormap`, `save_scene_3d_image`. Every run now writes rgb/bboxes/masks at top level **and** under `perception/`, plus `depth_colormap.png` and `scene_3d.png`.
- **Rerun bbox fix:** Live runs logged bboxes as root-level images without `Pinhole` — boxes appeared misaligned vs RGB. Now `rerun_utils.log_perception_to_rerun` logs `cam` transform + intrinsics, `cam/rgb`, `cam/bboxes` as native `Boxes2D` (pixel XYXY), and overlay PNGs under `cam/`.
- OpenAI bbox conversion lives in `bbox_utils.openai_box_to_gemini_normalized` (pixel -> internal 0-1000 gemini format).

## 2026-06-10 — OpenAI bbox v2 (pixel parse + SAM refine + retry)

- GPT-4o returns **pixel** `[xmin, ymin, xmax, ymax]` (not 0-1000). Added `parse_openai_box_2d` auto-detect + store `box_2d_pixels` / `box_2d_raw`.
- Send **PNG** (not JPEG) to OpenAI so coords match saved `rgb.png`.
- After SAM, **`refine_bboxes_from_masks`** tightens boxes from mask extents.
- If peach boxes aren't inside the `box` container, **retry detection once** with a correction prompt.
- Shared bbox pixel conversion in `perception/bbox_utils.py` (used by SAM2, visualization, Rerun).

## 2026-06-10 — VLM goal predicate sanitization

- OpenAI sometimes returns predicates referencing undetected objects (e.g. `on(yellow_fruit, box)` when `box` has no bbox) or wrong predicate type for pick tasks. `vlm_common.sanitize_grounded_atoms` drops invalid atoms and infers `holding(target)` from task text when appropriate.
- Updated `detect_and_translate_openai.txt` with pick/holding examples and require detecting containers mentioned in the task.
