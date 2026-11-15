# Desktop: mainboard sometimes stays on after shutdown

Board: ASUS TUF Z370-PLUS GAMING, BIOS 3004 (2021-07-12).

## What we know (2026-11-12)

- Linux shuts down cleanly every time. The journal reaches "System Power Off"
  for every boot (`journalctl -b -1 -n 10`).
- The kernel isn't hanging. Panic-on-hang is configured (`hung_task_panic`,
  `softlockup_panic`, `efi_pstore`), but no crash record has ever been saved,
  and `/var/lib/systemd/pstore` doesn't exist.
- So Linux sends the final ACPI power-off command and the board doesn't act on
  it. That points to firmware, or to a device that is armed to wake the PC.
- Three devices were armed to wake the PC from power-off (`/proc/acpi/wakeup`,
  S4): `GLAN` (Intel I219-V LAN), `XHC` (Intel USB), `PXSX` (ASMedia USB).

## Step 1, done in config: disable wake sources

`default.nix` has udev rules that turn off wakeup for those three devices, and
Wake-on-LAN on `enp0s31f6`.

Side effect: the PC can't be woken from suspend by USB keyboard or mouse. The
power button still works. Revert the `XHC`/`PXSX` lines if you rely on that.

Check after rebooting:

```console
grep enabled /proc/acpi/wakeup
```

None of the three should be listed. Then shut down about 10 times and count how
often the board stays on.

## Step 2, if it still happens: BIOS settings, one at a time

1. Advanced > APM Configuration:
   - ErP Ready = Enable (S4+S5)
   - Power On By PCI-E = Disabled
   - Power On By RTC = Disabled
2. Advanced > PCH-FW Configuration > PTT = Disable. Several ASUS boards report
   this fixes "fans stay on after Linux shutdown". Only do this if nothing uses
   the TPM: no TPM-backed LUKS unlock, no Windows BitLocker. Your LUKS unlock
   uses FIDO2, so check first.
3. Boot > Fast Boot = Disabled.

## Step 3, if it still happens: kernel USB workaround

Add `xhci_hcd.quirks=270336` to `boot.kernelParams`. This turns on the
XHCI_SPURIOUS_WAKEUP and XHCI_SPURIOUS_REBOOT workarounds (the Red Hat bug
below).

## Sources

- TrueNAS, ASUS board stays on after shutdown; fixed by turning off PTT/fTPM:
  https://forums.truenas.com/t/still-shutdown-issues-with-my-server-no-matter-what-i-do/58562
- TrueNAS, ASUS H87I-PLUS powers back on; fixed through the Intel xHCI mode:
  https://forums.truenas.com/t/asus-h87i-plus-immediately-powers-back-on-after-shutdown-solved-intel-xhci-mode/67663
- unRAID, Z370 board starts again after shutdown (xHCI quirk, WoL):
  https://forums.unraid.net/topic/89123-system-booting-immediately-after-shutdown/
- Arch forums, OS finishes shutdown but the ACPI power-off is ignored:
  https://bbs.archlinux.org/viewtopic.php?id=297688
- Red Hat bug 1189107, `xhci_hcd.quirks=270336`:
  https://bugzilla.redhat.com/show_bug.cgi?id=1189107
- Kernel bug 76291, xHCI spurious reboot on power-off:
  https://bugzilla.kernel.org/show_bug.cgi?id=76291

## Update (2026-11-15)

Step 1 only half worked: `GLAN` was still `enabled` after boot. The USB ones
were disabled. Two reasons:

- The `e1000e` driver loads after the PCI `add` event and arms wakeup again
  from the NIC's WoL setting. The PCI rule now also runs on `bind`.
- The ethtool rule matched `KERNEL=="enp0s31f6"`, but during the `add` event
  the card is still called `eth0`, so it never ran. It now matches
  `DRIVERS=="e1000e"` and uses `$name`.

So the shutdown test hasn't really been done yet. Rebuild, reboot, check
`grep enabled /proc/acpi/wakeup` shows nothing, then count shutdowns.
