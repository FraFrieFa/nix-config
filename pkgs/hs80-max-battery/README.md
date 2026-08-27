# HS80 MAX for KDE Plasma

Native NixOS support for the Corsair HS80 MAX Wireless receiver (`1b1c:0a97`).
It uses the Corsair Wireless V2 protocol implemented by HeadsetControl.

## Desktop tray

`hs80-max-tray` starts automatically in KDE Plasma. Its native tray menu shows:

- battery percentage and connection state;
- inferred charging/discharging state;
- boom-microphone mute state;
- auto-off timeout choices from disabled through 90 minutes;
- manual refresh and low-battery notifications.

Charging state is inferred from changes between battery samples because this
receiver's verified protocol does not report a direct charging flag.

## Command line

```console
hs80-max-battery --battery
hs80-max-battery --battery --plain
hs80-max-battery --battery --json
hs80-max-battery --battery --watch --interval 30
hs80-max-battery --inactive-time 15
hs80-max-battery --inactive-time 0
```

After the NixOS configuration is activated and the receiver is reconnected,
these commands run as the logged-in desktop user without `sudo`. The udev rule
uses `uaccess` and is restricted to this receiver's vendor protocol interface.
