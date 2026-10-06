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

## 2026-06-12 — Dual-camera MP4 sync during `--enable-recording`

- **Root cause:** `record_cameras` started SVO recording sequentially (hand vs external offset), and `convert_svo_to_mp4` used nominal camera FPS without ZED timestamps — MP4s had different start times/lengths.
- **Fix:** barrier-sync grab loops at record start; `convert_svos_to_mp4_synced` resamples both SVOs onto a shared timestamp grid (30 fps) and writes `recording_sync.json` per run.

- **Root cause:** `go_to_q()` in `motion_planning.py` called `client.close()` after executing motion, but `get_bamboo_client()` is a `@cache` singleton — same object as `container.robot`. Next line `open_gripper()` hit a dead ZMQ socket and the run aborted before the task prompt.
- **Fix:** removed `client.close()` from `go_to_q`; teardown in `tiptop_run` still closes the client on exit.
- **Normal flow after fix:** after capture move you should see `Ready for task` then the instruction prompt. `go_to_q` must use `container.robot` (not a separate cached client).
- **Arm doesn't move but "Motion planning took 0.00s":** check new logs `Joint distance to target` and `Executing N waypoints`. Isolate with `pixi run go-to-capture`. If execute fails, Bamboo/FCI on NUC (`tail /tmp/bamboo_control.log`).
- **Gripper failure no longer aborts run** — warns and continues to task prompt. Fix NUC `:5559` if needed.
- **`save_run_metadata` UnicodeDecodeError (2026-06-12):** `git diff` via subprocess used locale ASCII; fixed with `encoding=utf-8` in `recording.py`.
- **cuRobo pick planning fails from capture pose:** perception OK (~730 peach grasps) but all 32 particles fail approach motion (`robot_to_movables` only 167/256). Fixes: `calibrate-wrist-cam` for serial `10163006`, `go-to-home` then re-run, reduce table clutter, or type `exit` after failed plan instead of Ctrl+C.
- **ZED "CAMERA NOT DETECTED" after Ctrl+C:** interrupting during `cam.close()` leaves USB busy — wait 5s, avoid double Ctrl+C on teardown, unplug/replug wrist ZED if needed.
- **External ZED optional:** `get_external_camera()` returns `None` if serial unset or open fails — `tiptop-run` continues with hand cam only. Set `cameras.external.serial: ""` in `tiptop.yml` to skip permanently.

## 2026-06-10 — VLM goal predicate sanitization

- OpenAI sometimes returns predicates referencing undetected objects (e.g. `on(yellow_fruit, box)` when `box` has no bbox) or wrong predicate type for pick tasks. `vlm_common.sanitize_grounded_atoms` drops invalid atoms and infers `holding(target)` from task text when appropriate.
- Updated `detect_and_translate_openai.txt` with pick/holding examples and require detecting containers mentioned in the task.

## 2026-06-11 — Merged to tiptop `main`, deleted `lab/openai-vision-bbox-fixes`

- Fast-forward merge to `main`; local branch deleted. Complete test passed: `pytest test_bbox_utils`, Gemini VLM, full `detect_and_segment` (VLM+SAM2). Outputs: `tiptop/debug_bbox/complete_test/`.

## 2026-06-11 — Lab default VLM switched to Gemini

- `tiptop/config/tiptop.yml`: `provider: gemini`, `model: gemini-robotics-er-1.6-preview`. `GOOGLE_API_KEY` in gitignored `tiptop/.env`; `gemini.py` auto-loads `.env`.
- `apply_gemini_norm_bboxes` in `gemini.py` + full-res remap in `perception_wrapper` before SAM.
- Bbox test viz: `tiptop/debug_bbox/gemini_switch_test/`. OpenAI path kept but not default.

## 2026-06-11 — OpenAI bbox: use Structured Outputs, not json_object guessing

- **OpenAI docs:** Vision models have **no native pixel bbox API**. Recommended: **Structured Outputs** (`client.beta.chat.completions.parse`) + Pydantic schema + **1000×1000 grid** with explicit `ymin/xmin/ymax/xmax` fields. Bare `gpt-4o` alias does **not** support schema enforcement; use `gpt-4o-2024-08-06` or `gpt-4.1`.
- **What was wrong:** `json_object` + free-form `[xmin,ymin,xmax,ymax]` list + heuristic parsers → ambiguous on HD images; boxes landed on teddy/glass instead of box/peaches.
- **Fix:** `openai_schemas.py` + `openai_vision.py` structured parse; `apply_gemini_norm_bboxes` (no guessing); same 800px VLM resize as Gemini; default model `gpt-4o-2024-08-06`. Legacy `normalize_openai_bboxes` kept for old JSON only.
- **Limits:** GPT-4o spatial grounding is still weak vs dedicated detectors; **Gemini `gemini-robotics-er-1.6-preview`** is TiPToP upstream default if you have `GOOGLE_API_KEY`. SAM refines boxes after VLM.
- **Rerun logging was fine** — bad coords in `bboxes.json`. Re-run `tiptop-run` after pull.

## 2026-06-23 — RTX PRO 6000 Blackwell upgrade blocked on pci-blenderman

- **Full handoff:** [`docs/rtx-pro-6000-gpu-handoff.md`](docs/rtx-pro-6000-gpu-handoff.md) — read before any GPU/driver work.
- **Symptom:** With Pro 6000 installed, no video on GPU or motherboard iGPU; boot only works with card removed.
- **Machine:** MSI PRO Z790-P WIFI, i9-13900K, **64 GB RAM**, BIOS **A.30 (2022-11-24)** → flash **7E06vAJ** via M-FLASH (USB ready: `E7E06IMS.AJ0` on `/dev/sdb`).
- **Root cause (likely):** power (**4×8-pin → shipper adapter**), then **64 GB RAM < 96 GB VRAM**, then old BIOS. Not Linux driver until POST works.
- **After POST:** `nvidia-driver-580-open` (closed 580 wrong for Blackwell).

- **Lab VLM policy (2026-07-09):** Use **Gemini only** (`gemini-robotics-er-1.6-preview` in `tiptop.yml`). Do not set `TIPTOP_VLM_PROVIDER=openai`. `start-tiptop-clean.sh` unsets VLM env overrides. Need `GOOGLE_API_KEY` in `tiptop/.env`.

- **FoundationStereo Blackwell upgrade (2026-07-09):** Upgraded `FoundationStereo/pixi.toml` to `pytorch-gpu>=2.7` (resolves to 2.12.1 with **sm_120**). Fixed `scripts/server.py` `torch.load(..., weights_only=False)` for PyTorch 2.6+ checkpoint loading. Inference **~130s → ~1s** on RTX PRO 6000. Re-run `pixi install` in `FoundationStereo/` after pull.

## 2026-07-09 — NUC `start_gripper.sh` killed working gripper

- **`start_bamboo.sh` + `start_gripper.sh` in one SSH line:** if bamboo reports both ports up, skip gripper start. If gripper start runs anyway, it **kills** the live `gripper_server.py` then reconnects USB — Robotiq often fails immediately after kill (`Failed to contact gripper on /dev/ttyUSB0`). **Fix:** `start_gripper.sh` now exits early when `:5559` + process already healthy. **Recovery:** `ssh nuc 'bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh'` (retry once after ~5s if needed).

## 2026-07-24 — Second task fails: Rerun gRPC disconnected

- **Symptom:** After first run (esp. if Rerun window closed), next instruction crashes at `rr.init(..., spawn=True)` with `RuntimeError: gRPC connection ... gracefully disconnected`.
- **Cause:** Stale Rerun proxy from prior `spawn=True`; closing the viewer leaves the SDK connected to a dead endpoint.
- **Fix:** In `tiptop_run.py`, catch init failure → `rr.disconnect()` → retry once; if still failing, warn and continue without live viewer (perception/plan/execute still work).
- **Workaround without code:** don’t close Rerun between tasks, or restart `tiptop-run` / `start-tiptop-clean.sh` after closing it.

## 2026-07-13 — `INVALID_START_STATE_JOINT_LIMITS` before capture

- **Symptom:** `MotionGenStatus.INVALID_START_STATE_JOINT_LIMITS` in `go_to_capture`.
- **Cause:** Joint 6 past soft limit — e.g. `q=[0.91, -0.12, -0.82, -1.93, 2.86, 4.03, 0.30]` with J6≈4.03 > ~3.75 rad. cuRobo refuses to plan from an illegal start.
- **Fix (Desk):** Programming mode → gently fold wrist (J6) back toward ~1.5–3.0 rad → then:
  ```bash
  cd ~/Desktop/TIPTOP/tiptop && pixi run go-to-home
  # or
  pixi run go-to-capture
  ```
- Do **not** re-run `tiptop-run` until `get-joint-positions` shows J6 ≤ ~3.7.

## 2026-07-13 — Bamboo `Net Exception` = Polymetis still holding FCI

- **Symptom:** `BambooConnectionError: ... Failed to get robot state: Exception: Net Exception` while `:5555` is listening.
- **Cause:** DROID/Polymetis and Bamboo both running on NUC (`:4242` / `:50051` + `:5555`). Only **one** FCI client at a time.
- **Fix:** Stop Polymetis on NUC, then restart Bamboo:
  ```bash
  ssh nuc 'pkill -f "scripts/server/run_server.py"; pkill -9 run_server; pkill -f launch_robot.py; pkill -f launch_gripper.py; bash ~/Desktop/TIPTOP/scripts/nuc/stop_bamboo.sh; sleep 2; bash ~/Desktop/TIPTOP/scripts/nuc/start_bamboo.sh; sleep 3; bash ~/Desktop/TIPTOP/scripts/nuc/start_gripper.sh'
  ```
- Then on Desk: unlock → Execution → **Activate FCI**. Verify: `pixi run get-joint-positions`.

## 2026-07-09 — `robotman` bootstrap completed

- **`git` not in system PATH** — `sudo apt install git` needs password; used `conda install -y -c conda-forge git` via `/home/pci/anaconda3/bin/conda`. Add `/home/pci/anaconda3/bin` to PATH before bootstrap, or install system git.
- **`curl` also missing** — bootstrap fell back to `wget` for pixi installer.
- **Bootstrap OK** — `pixi install` + `setup-planners` for tiptop; M2T2 + FoundationStereo `pixi install` + setup (FoundationStereo `flash-attn` build failed: no `nvcc` in env; server still runs without it).
- **Smoke tests passed:** `tiptop-run -h`, `pytest tests/test_bbox_utils` (4 passed).
- **M2T2 demo:** server `:8123` + `m2t2_client_demo.py sample_data/real_world/00 --no-viz` → 550 grasps. Default demo hangs without `meshcat-server` (use `--no-viz` headless).
- **FoundationStereo demo:** server `:1234` inference ~68s, HTTP 200. `client_example.py` hangs on `cv2.imshow` when no DISPLAY — use `--output depth.npy` and skip viz, or run with display.
- **Blackwell PyTorch mismatch in M2T2/FoundationStereo** — pinned `pytorch-gpu==2.4.1` warns sm_120 unsupported; inference still runs (slow/warning). **tiptop** env has torch 2.7.1 with sm_120 OK.
- **ZED SDK** still not installed — run `cd $TIPTOP_DIR/tiptop && pixi run install-zed` when cameras plugged in.
- **Full robot demo** still needs NUC Bamboo + Desk FCI + perception servers — see `docs/tiptop-experiment-runbook.md`.

## 2026-07-09 — Workstation migration to `robotman` (abandon pci-blenderman)

- **New workstation:** `robotman` at `pci@10.50.167.32` — RTX PRO 6000 Blackwell, 125 GB RAM, Ubuntu 24.04, driver 580.159.03 working.
- **Old workstation:** `pci-blenderman` (`10.50.206.40`) abandoned — Pro 6000 never POSTed there (64 GB RAM).
- **Agent handoff:** [`docs/workstation-migration-handoff.md`](docs/workstation-migration-handoff.md) — read first on new machine.
- **Migration:** rsync `~/Desktop/TIPTOP` excluding `.pixi/` and `tiptop_outputs/`; rebuild envs with `scripts/setup/bootstrap-new-workstation.sh`.
- **Secrets:** `tiptop/.env` rsync'd (gitignored); bootstrap adds `TIPTOP_DIR` + `.env` sourcing to `~/.bashrc`.
- **Uncommitted `tiptop/` changes** on old machine (zed_camera, recording, tiptop_run, motion_planning) were rsync'd — not on `lab/main` yet.
- **ZED SDK** not on `robotman` yet — run `pixi run install-zed` after bootstrap.
- **NUC/robot IPs unchanged** (`192.168.1.7` / `192.168.1.11`); update docs that still say `pci-blenderman` / `192.168.1.6`.

## 2026-07-24 — TiPToP home CLI name

- Canonical script is **`go-home`** (`pyproject.toml` → `tiptop.scripts.go_to_conf:go_to_home_entrypoint`), not `go-to-home`. Older notes that say `pixi run go-to-home` are wrong; use `cd ~/Desktop/TIPTOP/tiptop && pixi run go-home`.
- Operator one-liner logged at `/home/pci/Desktop/robot_entries/tiptop_go_home.md`.

## 2026-07-24 — go-home live test on robotman

- **Polymetis + Bamboo both up** → Bamboo `Net Exception`. Stop Polymetis with **specific** patterns (`scripts/server/run_server.py`, `polymetis/build/run_server`) — bare `pkill -f run_server` kills the SSH shell that contains that substring.
- After Bamboo restart, first state read can be `UDP receive: Timeout` until Desk FCI is active and/or Bamboo is restarted again; then `get-joint-positions` works.
- **`INVALID_START_STATE_JOINT_LIMITS`:** not only J6≳3.75. cuRobo soft mins/maxes include **J4/panda_joint5 ≈ ±2.8065** (saw failure at J4≈−2.824) and **J5/panda_joint6 ≥ 0.5445**. Fold offending joints slightly inside limits via Bamboo `execute_joint_impedance_path`, then `pixi run go-home --time-dilation-factor 0.3`.
- **Verified home:** after recovery + `go-home`, joints matched `q_home` within ~0.007 rad L2 / ~0.006 rad max abs.
- **Fresh one-liner:** `bash ~/Desktop/TIPTOP/scripts/setup/tiptop-go-home-fresh.sh` — NUC `restart_bamboo_fresh.sh` (kill Polymetis + restart Bamboo) → soft-limit fold → **`go-to-capture`** (cam home). Logged in `/home/pci/Desktop/robot_entries/tiptop_go_home.md`. Sync `scripts/nuc/*.sh` to NUC after pull.
- **`open terminal failed: not a terminal`:** `RunBambooController start` tries to attach tmux over non-interactive SSH and exits non-zero under `set -e`, aborting `tiptop-go-home-fresh.sh` even after "Launched servers!". Fix: `BAMBOO_HEADLESS=1` / no-TTY → nohup path in `start_bamboo.sh`; `restart_bamboo_fresh.sh` always sets headless. Sync both scripts to NUC.
- **Lab home = capture pose (2026-07-24):** Old `q_home` tuck `[0, -0.628, …, 1.885, 0]` is not the pose TiPToP uses for perception. Set `q_home := q_capture` in `tiptop.yml`; fresh reset calls `go-to-capture`; `tiptop_run` returns to capture after plan execution.
