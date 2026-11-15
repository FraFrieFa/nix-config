# HS80 MAX: bad microphone after a fresh boot

## The problem

After a fresh boot the mic sometimes sounds bad. Turning the headset off and on
fixes it, but sometimes it takes several tries. Once it is good, it stays good.

## What we know (2026-11-12)

- **Bad state:** your voice is cut off at about 4 kHz (phone-call quality),
  with distortion noise between 12 and 16 kHz.
- **Good state:** the audio is clean and reaches about 12 kHz.
- **The USB side is the same in both states.** The receiver always reports a
  48 kHz, 16-bit mono capture (`/proc/asound/card0/stream0`). So the quality
  drops on the wireless link between the headset and the receiver.
- **Ruled out:**
  - Sample rate: forcing PipeWire to 16 kHz and back
    (`pw-metadata -n settings 0 clock.force-rate 16000`, then `0`) didn't help.
  - Bluetooth on the PC: this PC has no Bluetooth adapter.
  - Apps holding the mic: with TeamSpeak and Steam closed, one headset restart
    still came back bad.
  - A phone connected over Bluetooth: none is connected.
- **Still open:**
  - Does resetting the USB receiver re-roll the mic mode, the way a headset
    restart does? This needs root, so it hasn't been tested yet.
  - Does any HID property read differently in the bad state? A good-state
    baseline is saved; see the next step.

## What to do when it is bad again

Don't restart the headset yet. First run:

```console
/etc/nixos/pkgs/hs80-max-battery/mic-debug/check.sh bad
```

Talk normally while it records. It will:

1. record 6 s of your voice and print a verdict. It compares the 12–15 kHz band
   with the 8–10 kHz band: about +14 dB means bad, about −9 dB means good. It
   only works while you are talking.
2. read every V2 HID property from the receiver and the headset (read-only,
   using the same protocol as `hs80_max_battery.py`) and save them to
   `bad-<timestamp>.json`.
3. print every property that differs from the good baseline
   (`good-20261112-1104.json`). Battery level is ignored.

Then test the receiver reset:

```console
sudo nix shell nixpkgs#usbutils --command usbreset 1b1c:0a97
./check.sh after-reset
```

Repeat the reset a few times if needed, and note whether it ever turns good.

## How the results decide the fix

| Result | Fix |
| --- | --- |
| A property differs between bad and good | Best case. Try writing the good value with the V2 "set" command (byte 3 = `0x01`, as in `set_inactive_time`). If that works, the tray app can check and fix it automatically after the headset connects. Fully automatic, no root. |
| No difference, but `usbreset` fixes it | A small root service or udev helper resets the receiver. The tray app triggers it when the mic is in use, you're talking, and the audio check says BAD. |
| Neither helps | The mode is decided inside the headset. Try a firmware update in iCUE on Windows, check the phone Bluetooth connection, or at least get a desktop notification ("restart headset") from the audio check. |

## Files

- `check.sh`: record, analyze, read properties and compare (the one command to run)
- `analyze.py`: the audio verdict (needs numpy; `check.sh` gets it via nix shell)
- `dump_props.py`: read-only dump of all receiver and headset properties
- `diff_props.py`: compare two dumps
- `good-20261112-1104.json`: good-state property baseline
- `ref-bad.wav`, `ref-good.wav`: reference recordings of both states

Properties that answer in the good state (receiver endpoint `0x08`, headset
endpoint `0x09`): receiver 03, 11, 12, 13, 36; headset 03, 0d, 0e (auto-off ms),
0f (battery ×10), 10, 11, 12, 13, 3a, 47, 53, a6 (mic mute).
