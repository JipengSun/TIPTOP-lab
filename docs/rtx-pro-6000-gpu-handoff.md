# Agent handoff — RTX PRO 6000 Blackwell upgrade on pci-blenderman

**Created:** 2026-06-24  
**Machine:** `pci-blenderman` (`192.168.1.6`)  
**Status:** **Phase A done** — BIOS updated; **Phase C pending** (Pro 6000 POST test)  
**Previous GPU:** RTX 4090 (worked)  
**Target GPU:** RTX PRO 6000 Blackwell Workstation Edition  

**Read this doc first** before attempting driver installs, CUDA changes, or TiPToP/DROID GPU work.

Related lab docs:
- [`../improvement.md`](../improvement.md) — short summary entry under 2026-06-23
- [`../workstation-agent-handoff.md`](../workstation-agent-handoff.md) — TiPToP/Bamboo (separate from GPU issue)

---

## Executive summary

| Item | Status |
|------|--------|
| Symptom with Pro 6000 | **No video on GPU or motherboard iGPU; cannot enter BIOS reliably** |
| Symptom with card removed | **Boots normally on Intel iGPU** |
| RTX 4090 in same slot | **Worked** (display + compute) |
| Root cause layer | **Firmware/POST (not Linux driver)** — OS never loads with card installed |
| BIOS flash USB | **Prepared** — `E7E06IMS.AJ0` on FAT32 stick (label `MSI_BIOS`) |
| BIOS actually flashed | **Done** — `A.J0` (2026-04-01); was `A.30` (2022-11-24) |
| NVIDIA driver | `nvidia-driver-580` **closed** installed — run `/home/pci/setup-nvidia-open-driver.sh` after POST works |
| Forum post drafted | Yes — user may have posted on NVIDIA Developer Forums (≤4 links for new accounts) |

**Do not** spend time on `nvidia-smi`, DDU, or driver purge until the machine **POSTs with the Pro 6000 installed** and `lspci` shows the NVIDIA device.

---

## Hardware (verified on machine)

| Component | Details |
|-----------|---------|
| Hostname | `pci-blenderman` |
| IP | `192.168.1.6` |
| Motherboard | MSI **PRO Z790-P WIFI** (MS-7E06) |
| CPU | Intel **i9-13900K** (iGPU UHD 770, PCI `8086:a780`) |
| System RAM | **64 GB** DDR5 (~62.5 GiB usable) |
| BIOS (last seen) | **A.30** dated **2022-11-24** |
| BIOS target | **7E06vAJ** (May 2026) — file `E7E06IMS.AJ0` |
| OS | Ubuntu **22.04.5 LTS**, kernel **6.8.0-111-generic** |
| Boot disk | NVMe Samsung 980 PRO 2TB |
| Secure Boot | Disabled |
| PSU | **Not recorded in agent session** — confirm model/wattage with operator |

GPU state during last agent session: **Pro 6000 physically removed** (only Intel iGPU visible in `lspci`).

---

## Problem description

### Symptom

1. Install RTX PRO 6000 Blackwell WS in top PCIe x16 slot.
2. Power on with monitor on **GPU ports** → **no signal**.
3. Move monitor to **motherboard** HDMI/DP → **still no signal**.
4. Remove Pro 6000, reboot → **motherboard display works**.

This pattern means failure happens during **early boot / GPU firmware init**, before the OS and before NVIDIA drivers matter.

### What this is NOT (for this symptom)

- Missing or wrong Linux driver (driver loads after POST)
- GeForce vs Quadro “driver conflict” at OS level
- GRUB `pci=realloc` issues (those apply after kernel starts)
- Display Mode Selector (only relevant after POST; Server Edition default display-off)

---

## Root cause hypotheses (ranked)

| Priority | Cause | Evidence |
|----------|-------|----------|
| **1** | **Power cabling** — need shipper **4×8-pin → 12V-2×6 adapter** + **4 separate PSU 8-pin cables** | [NVIDIA forum 372649](https://forums.developer.nvidia.com/t/rtx-pro-6000-blackwell-workstation-edition-not-detected-multiple-systems-two-separate-units/372649): native PSU 12V-2×6 failed; included adapter fixed POST. Operator uses shipper adapter + PSU cables that worked on 4090 — **verify all 4 adapter inputs connected, no daisy-chain**. |
| **2** | **64 GB system RAM < 96 GB GPU VRAM** | [NVIDIA QSG PDF](https://images.nvidia.com/aem-dam/en-zz/Solutions/design-visualization/quadro-product-literature/nvidia-rtx-pro-blackwell-online-qsg.pdf): “System memory: greater than or equal to GPU memory; twice recommended.” [Forum 342479](https://forums.developer.nvidia.com/t/will-rtx-pro-6000-blackwell-prevent-boot-if-sysmem-graphicsmem/342479): same no-POST symptom, 64 GB RAM, 4090 worked — **no confirmed “128 GB fixed it” reply**. |
| **3** | **BIOS too old** (A.30 from 2022) | Latest MSI **7E06vAJ** (2026). Blackwell did not exist when A.30 shipped. May affect PCIe BAR, iGPU routing, Gen5 training. |
| **4** | **Resizable BAR / MMIO** | [Forum D4 thread](https://forums.developer.nvidia.com/t/help-please-2x-rtx-6000-pro-blackwell-motherboard-code-d4-pci-resource-allocation-error-out-of-resources/366642): disable ReBAR to fix resource errors. Recommend **ReBAR disabled** for initial bring-up. |
| **5** | **Wrong Linux driver** | Closed `nvidia-driver-580` installed; Blackwell requires **open** module per [forum 332701](https://forums.developer.nvidia.com/t/rtx-pro-6000-blackwell-workstation-edition-driver-support/332701). **Only relevant after POST succeeds.** |

---

## Power wiring (critical — verify with operator)

Official [NVIDIA RTX PRO Blackwell QSG](https://images.nvidia.com/aem-dam/en-zz/Solutions/design-visualization/quadro-product-literature/nvidia-rtx-pro-blackwell-online-qsg.pdf):

> For **RTX PRO 6000**, connect **four separate** PCIe 8-pin cables from the PSU to the **included** NVIDIA Quad 8-pin adapter.

Correct chain:

```text
[PSU 8-pin #1] ──┐
[PSU 8-pin #2] ──┤
[PSU 8-pin #3] ──┼──> [Shipper 4×8 → 12V-2×6 adapter] ──> [Pro 6000]
[PSU 8-pin #4] ──┘
```

**Wrong:**
- Native PSU 12VHPWR/12V-2×6 **direct to GPU** (failed in forum 372649)
- Only **3** of 4 adapter ports filled (4090 habit)
- Daisy-chained splits filling 4 ports from 2 PSU cables

Operator stated: shipper adapter is used; PSU 8-pin cables are theirs (worked on 4090). **Agent must confirm 4/4 connections and separate PSU ports.**

---

## Work completed by prior agent session

| Step | Status | Notes |
|------|--------|-------|
| Machine inventory | Done | `lspci`, DMI, RAM, BIOS version |
| BIOS package downloaded | Done | `/home/pci/Downloads/msi-bios/7E06vAJ/` |
| USB prepared for M-FLASH | Done | `/dev/sdb` → FAT32 label `MSI_BIOS`, file `E7E06IMS.AJ0` at root |
| USB setup script | Done | `/home/pci/setup-bios-usb.sh` (re-runnable with sudo) |
| SHA256 verified on USB | Done | Matches source `E7E06IMS.AJ0` |
| NVIDIA forum post draft | Done | ≤4 links version (new user limit) |
| BIOS flash at firmware | **Unknown** | User may not have completed M-FLASH yet |
| Pro 6000 POST test after BIOS | **Not done** | |
| `nvidia-driver-580-open` install | **Not done** | Wait until POST works |
| RAM upgrade to 128 GB | **Not done** | |

### USB paths (if re-check needed)

```bash
lsblk /dev/sdb
ls -la /media/pci/MSI_BIOS/E7E06IMS.AJ0   # when mounted
sha256sum /home/pci/Downloads/msi-bios/7E06vAJ/E7E06IMS.AJ0
```

To recreate USB (erases stick):

```bash
sudo bash /home/pci/setup-bios-usb.sh
```

---

## Recovery procedure (strict order)

### Phase A — BIOS update (GPU removed)

1. Pro 6000 **removed**; monitor on **motherboard**.
2. USB with `E7E06IMS.AJ0` plugged in (rear port).
3. Reboot → **Delete** → **M-FLASH** → select `E7E06IMS.AJ0` → wait → auto reboot.
4. Verify: `cat /sys/class/dmi/id/bios_version` — should **not** be `A.30`.

### Phase B — BIOS settings (before installing GPU)

| Setting | Value |
|---------|--------|
| Primary Display / Init Display | **IGFX / Onboard** |
| iGPU Multi-Monitor | **Enabled** |
| Above 4G Decoding | **Enabled** |
| Resizable BAR | **Disabled** |
| CSM | **Disabled** |
| PCIe slot speed | **Gen4** (try first) |
| Secure Boot | Disabled |

Save and shut down.

### Phase C — First POST test with Pro 6000

1. Install Pro 6000; **4× PSU 8-pin → shipper adapter → GPU**.
2. Monitor on **motherboard** (not GPU).
3. Power on.

| Outcome | Next |
|---------|------|
| BIOS / Ubuntu on iGPU | → Phase D |
| Still black everywhere | → Phase E |

### Phase D — Software (only after Phase C succeeds)

```bash
lspci | grep -i nvidia    # must show NVIDIA device

sudo apt purge 'nvidia-driver-*' 'linux-modules-nvidia-*'
sudo apt update
sudo apt install nvidia-driver-580-open
sudo reboot

nvidia-smi                # should show RTX PRO 6000
```

Then move monitor to GPU ports and reboot.

### Phase E — If Phase C still fails

1. Re-verify **4/4 power** on adapter, separate PSU ports.
2. Clear CMOS; re-apply Phase B settings.
3. Upgrade RAM to **128 GB** (64 GB < 96 GB VRAM — NVIDIA documented minimum).
4. Try different PSU / cables if available.
5. Follow up on NVIDIA forum post or create one using draft in chat history.

---

## Software state (card removed, last check)

```bash
# GPU PCI — only Intel iGPU when card removed
lspci | grep -iE 'vga|nvidia'
# 00:02.0 VGA ... Intel Corporation Device [8086:a780]

# Driver packages (closed — wrong for Blackwell)
dpkg -l | grep nvidia-driver
# nvidia-driver-580

# Module not loaded / no device
nvidia-smi
# "couldn't communicate with the NVIDIA driver"
```

---

## Common bad advice to ignore (for this symptom)

Generic “GPU upgrade” guides often suggest:

- DDU / Safe Mode driver wipe **first** — irrelevant on Linux when machine won't POST
- Enable **Resizable BAR** — often makes Pro 6000 **worse** on consumer boards
- Single native **12VHPWR** cable — contradicted by forum 372649
- 1200W+ PSU as hard requirement — quality **1000W** with correct cabling is commonly sufficient
- Alienware / CMOS / Dell-specific fixes — wrong platform (custom MSI build)

---

## Checklist for next agent

- [ ] Confirm current BIOS version (`/sys/class/dmi/id/bios_version`)
- [ ] Confirm whether M-FLASH was completed
- [ ] Confirm PSU model/wattage and **count of 8-pin cables on adapter (must be 4)**
- [ ] Confirm Pro 6000 SKU (Workstation vs Server vs Max-Q) and board partner
- [ ] Apply Phase B BIOS settings
- [ ] Phase C POST test with monitor on motherboard
- [ ] If POST OK: install `nvidia-driver-580-open`, verify `nvidia-smi`
- [ ] If POST fails: RAM upgrade path vs power rewire
- [ ] Update this doc with outcomes

---

## References (≤4 links if posting as new forum user)

1. Power adapter fix: https://forums.developer.nvidia.com/t/rtx-pro-6000-blackwell-workstation-edition-not-detected-multiple-systems-two-separate-units/372649  
2. RAM vs VRAM question: https://forums.developer.nvidia.com/t/will-rtx-pro-6000-blackwell-prevent-boot-if-sysmem-graphicsmem/342479  
3. Official RAM requirement (QSG PDF): https://images.nvidia.com/aem-dam/en-zz/Solutions/design-visualization/quadro-product-literature/nvidia-rtx-pro-blackwell-online-qsg.pdf  
4. Open driver requirement: https://forums.developer.nvidia.com/t/rtx-pro-6000-blackwell-workstation-edition-driver-support/332701  

Additional (not for 4-link-limited posts):

- ReBAR / D4: https://forums.developer.nvidia.com/t/help-please-2x-rtx-6000-pro-blackwell-motherboard-code-d4-pci-resource-allocation-error-out-of-resources/366642  
- MSI BIOS download: https://www.msi.com/Motherboard/PRO-Z790-P-WIFI/support  
- Power guidelines: https://www.nvidia.com/workstationpowerguidelines  

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-24 | Initial handoff doc after troubleshooting session; USB prepared; BIOS flash pending |
