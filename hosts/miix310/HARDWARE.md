# Lenovo IdeaPad Miix 310-10ICR — Hardware Status on NixOS

Model: **80SG** · 10.1" 2-in-1 tablet with detachable keyboard

Legend: ✅ working · ⚠️ partial/intermittent · ❌ broken · 🚫 not present · 📋 not yet tested

---

## Processor & Memory

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| CPU | Intel Atom x5-Z8350, 4 cores @ 1.44 GHz (burst ~1.68 GHz), Cherry Trail | ✅ | `intel_idle.max_cstate=1` set to prevent deep-sleep freezes |
| RAM | 4 GB DDR3L-1600 | ✅ | — |
| zRAM swap | 1.9 GB compressed swap | ✅ | Enabled in base.nix |
| Thermal | `thermald` daemon | ✅ | Added; manages Cherry Trail TDP budget |

---

## Storage

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| eMMC | 64 GB Hynix HCG8e (mmcblk0), SDHCI ACPI | ✅ | `sdhci_acpi` forced into initrd for faster detection |
| Partitioning | p1: 2 GB vfat /boot (shared), p2: 26 GB btrfs (CachyOS), p3: 25 GB ext4 / (NixOS) | ✅ | Dual-boot, shared EFI; `canTouchEfiVariables = false` |

---

## Display & GPU

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| GPU | Intel HD Graphics 400 (Cherryview, device ID 22b0), i915 driver | ✅ | `i915.force_probe=*` required |
| Display | 10.1" IPS DSI panel, native 1280×800 (landscape), used portrait 800×1280 | ✅ | `video=DSI-1:800x1280@60,rotate=90` in kernel params |
| Backlight | `intel_backlight`, 0–100 range, controlled via `brightnessctl` | ✅ | — |
| Early boot display | Blank screen for ~20 s until i915 loads | ⚠️ | `video=efifb:off` prevents simpledrm conflict; no clean fix without i915 in initrd (breaks stride) |
| Auto-rotate | `iio-sensor-proxy` + `monitor-sensor` script exec'd from sway | ⚠️ | Infrastructure in place; **orientation mapping needs physical testing** — adjust the `normal/left-up/right-up/bottom-up` → sway transform mapping in `default.nix` after testing |

---

## Connectivity

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| WiFi | Realtek RTL8723BS (r8723bs staging module, SDIO device) | ✅ | Staging driver warning is cosmetic; scan and connect work fine |
| Bluetooth | RTL8723BS combo chip (same hardware as WiFi) | 📋 | Module loaded (`r8723bs`); not yet tested |
| USB | Intel xHCI USB 3.0 (xhci_pci) | ✅ | — |
| USB Ethernet | ASIX AX88179 Gigabit (USB adapter via Genesys USB 3.0 hub) | ✅ | `enp0s20u4u1c2` — note: external adapter, not built-in |
| LTE / modem | Some SKUs may include a modem; none detected on this unit | 🚫 | ArchWiki notes modem as present on some variants |

---

## Audio

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| Internal codec | Realtek RT5645 (I2C, `cht-bsw-rt5645` machine driver) | ⚠️ | **Intermittent I2C timing race at boot** — rt5645 sometimes misses its probe window on I2C bus; `rt5645-reprobe.service` re-binds it at boot |
| Internal speakers / headphone jack | Driven by RT5645 | ⚠️ | Works when codec probes; **UCM profile needed** for correct volume levels — see fix below |
| HDMI audio | Intel LPE Audio (snd_hdmi_lpe_audio, card 0) | ✅ | Works when HDMI connected; 3 virtual devices |
| Microphone | RT5645 digital mic | ⚠️ | Depends on RT5645 probe succeeding |

**Audio UCM fix** (volume too low when audio works): The `chtrt5645` UCM profile ships with `alsa-ucm-conf`. Ensure pipewire picks it up; if volume is still low, verify `/run/current-system/sw/share/alsa/ucm2/chtrt5645/` exists. Source: [vovan47/miix310](https://github.com/vovan47/miix310), [ArchWiki](https://wiki.archlinux.org/title/Lenovo_IdeaPad_Miix_310-10ICR).

---

## Input

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| Touchscreen | FocalTech FTSC1000 (I2C HID, 0x2808:0x1015) | ✅ | `tap enabled`, mapped to DSI-1 in sway |
| Detachable keyboard | SIPODEV USB Composite Device SP-1029H (USB HID) | ✅ | Auto-detected as keyboard + touchpad |
| Power button | Via ACPI (`tiny_power_button`) | ✅ | — |
| Volume / brightness keys | ACPI video bus | ✅ | Wired to `brightnessctl` / `pactl` in sway config |
| Accelerometer | Kionix KXCJK-1013 (kxcjk1013, `iio:device0`, I2C KIOX000A) | ✅ | Hardware working; iio-sensor-proxy exposes orientation events |

---

## Power Management

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| Battery | AXP288 fuel gauge (`axp288_fuel_gauge`) | ✅ **FIXED** | Was blacklisted; unblocked — reports capacity, voltage, health |
| AC / charger | AXP288 charger (`axp288_charger`) | ❌ | **Blacklisted** — causes repeated I2C5 timeouts when loaded; AC state not reported to userspace |
| PMIC | AXP288 (axp20x-i2c, I2C5 / INT33F4) | ⚠️ | Core driver loads; single IRQ-status timeout at boot; IRQ mask sync fails (I2C5 unreliable) — power button via PMIC (`axp20x_pek`) may miss events |
| upower | Battery monitoring daemon | ✅ | `services.upower.enable = true` |
| swayidle | Dim (2 min) → lock (5 min) → DPMS off (6 min) | ✅ | Configured in sway config |

---

## Camera

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| Front camera | OmniVision OV2680 (ov2680 module, I2C OVTI2680:01) | ❌ | Deferred probe — waiting for `fwnode graph endpoint`. Requires `intel_atomisp2` staging driver + firmware blob. **No mainline fix as of 2025.** |
| Rear camera | Likely OV5648 | ❌ | Same AtomISP2 dependency. Not working on any mainline kernel. |
| AtomISP2 PM | `intel_atomisp2_pm` power manager | ✅ | Loaded; keeps ISP powered — but full ISP driver absent |

**Camera note:** CachyOS also has no working camera on this device. The OV2680 sensor needs the out-of-tree `intel_atomisp2` driver and an ACPI firmware quirk for the AXP PMIC power sequencing. No upstream fix expected soon.

---

## Security & Misc

| Component | Details | Status | Notes |
|-----------|---------|--------|-------|
| TPM | MSFT0101 TPM 2.0 | ✅ | Hardware present; takes ~10.9 s to enumerate at boot (hardware limit) |
| Intel TXE | Intel Trusted Execution Engine (mei_txe) | ✅ | Loaded |
| Intel MEI | Management Engine Interface | ✅ | Loaded |
| GPS | — | 🚫 | Not present on any Miix 310 SKU |
| NFC | — | 🚫 | Not present |
| Fingerprint | — | 🚫 | Not present |

---

## Boot Time

| Phase | Time | Status | Notes |
|-------|------|--------|-------|
| Firmware (UEFI) | 9.1 s | ⚠️ | Hardware limit — cannot be reduced in software |
| Bootloader (systemd-boot) | 7.9 s | ⚠️ | Mostly UEFI handoff overhead |
| Kernel | 1.9 s | ✅ | — |
| initrd | 7.6 s | ✅ **improved** | `sdhci_acpi` forced early; was 8.4 s |
| Userspace to graphical.target | 14.5 s | ⚠️ | TPM (10.9 s) and eMMC enumeration (9.9 s) are hardware limits; `NetworkManager-wait-online` disabled |
| **Total** | **~45 s** | ⚠️ | Firmware+loader (17 s) are the dominant cost and cannot be eliminated |

**Boot display:** Screen is blank from power-on until i915 loads at ~20 s. This is intentional — `video=efifb:off` prevents simpledrm from grabbing the ACPI framebuffer with wrong rotation, which was causing display glitches and suspected freezes.

---

## Desktop Environment

| Feature | Implementation | Status | Notes |
|---------|---------------|--------|-------|
| Compositor | Sway (Wayland tiling WM) | ✅ | Low CPU/RAM overhead; good touch support |
| Status bar | Waybar with battery, backlight, audio, wifi, clock | ✅ | Catppuccin Mocha theme |
| Launcher | Fuzzel | ✅ | — |
| Terminal | Foot (GPU-accelerated) | ✅ | — |
| Notifications | Mako | ✅ | — |
| On-screen keyboard | wvkbd (`$mod+o`) | ✅ | `wvkbd-mobintl` layout for tablet use |
| Screen lock | swaylock (plain `#1e1e2e`) | ✅ | Triggered by swayidle and before-sleep |
| Auto-rotate | iio-sensor-proxy + monitor-sensor script | ⚠️ | Service runs; orientation→transform mapping needs physical testing |
| Greeter | tuigreet → sway | ✅ | — |
| Performance tuning | `intel_idle.max_cstate=1`, thermald, zRAM swap | ✅ | — |

---

## Known Remaining Issues

1. **Audio probe race** — RT5645 misses I2C probe ~50% of boots. The `rt5645-reprobe.service` attempts a rebind after boot but cannot fix the underlying I2C5 bus timing. Consider a kernel parameter investigation or DSDT override in the future.
2. **Camera** — No fix possible on mainline kernel. Would require CachyOS/staging atomisp2 driver.
3. **AXP288 IRQ** — `Failed to sync masks` at boot. Cosmetic in practice (battery polling still works) but means charge-event interrupts don't fire.
4. **Auto-rotate orientation** — The `normal/bottom-up/left-up/right-up` → sway transform mapping in `default.nix` (`autoRotateScript`) may need swapping after physical testing.
5. **Boot blank screen** — 20 s of black before i915. Unavoidable without loading i915 in initrd (which breaks display stride on this panel).

---

## Sources

- [ArchWiki — Lenovo IdeaPad Miix 310-10ICR](https://wiki.archlinux.org/title/Lenovo_IdeaPad_Miix_310-10ICR)
- [vovan47/miix310 — Linux info repo](https://github.com/vovan47/miix310)
- [linux-hardware.org probe #c0eaa49f90](https://linux-hardware.org/index.php?probe=c0eaa49f90)
- [Lenovo PSREF — Miix 310-10ICR spec sheet](https://psref.lenovo.com/syspool/Sys/PDF/Lenovo_Tablets/ideapad_Miix_310_10/ideapad_Miix_310_10_Spec.pdf)
- [Xubuntu on Miix 310 — Lenovo Forums](https://forums.lenovo.com/t5/Ubuntu/Xubuntu-successfully-installed-on-Miix-310-10ICR-everything-but-camera-works/m-p/5208218)
