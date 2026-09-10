{ config, lib, pkgs, ... }:
let
  repeat = config.local.keyboard.repeat;

  # `alacritty msg create-window` exits 0 and silently does nothing when no
  # daemon is listening, so its exit status cannot drive a fallback. Probe for
  # a live daemon process instead, and spawn a standalone window otherwise.
  terminalScript = pkgs.writeShellScript "terminal" ''
    if ${pkgs.procps}/bin/pgrep -u "$(${pkgs.coreutils}/bin/id -u)" -f 'alacritty --daemon' >/dev/null 2>&1; then
      exec ${pkgs.alacritty}/bin/alacritty msg create-window
    fi
    exec ${pkgs.alacritty}/bin/alacritty
  '';

  # Maps the touchscreen onto the panel for a given xrandr rotation.
  #
  # `xinput map-to-output` is unreliable on this DSI panel, so the coordinate
  # transformation matrix is set explicitly instead. Note that the FTSC1000
  # exposes *two* devices with the same name -- a pointer and a spurious
  # "UNKNOWN" keyboard node -- so only the pointer half may be touched.
  autoRotateScript = pkgs.writeShellScript "auto-rotate" ''
    # Wait for X and i3 to be ready.
    sleep 2

    touchscreen_ids() {
      # --short lists pointers above the keyboard section; stop at the divider.
      ${pkgs.xinput}/bin/xinput list --short \
        | ${pkgs.gnused}/bin/sed -n '/Virtual core keyboard/q; p' \
        | ${pkgs.gnugrep}/bin/grep -Ei 'touchscreen|FTSC1000' \
        | ${pkgs.gnugrep}/bin/grep -oE 'id=[0-9]+' \
        | ${pkgs.coreutils}/bin/cut -d= -f2
    }

    map_touchscreen() {
      rotation="$1"
      case "$rotation" in
        normal)   matrix="1 0 0 0 1 0 0 0 1" ;;
        right)    matrix="0 1 0 -1 0 1 0 0 1" ;;
        inverted) matrix="-1 0 1 0 -1 1 0 0 1" ;;
        left)     matrix="0 -1 1 1 0 0 0 0 1" ;;
        *) return 0 ;;
      esac
      touchscreen_ids | while IFS= read -r id; do
        [ -n "$id" ] || continue
        ${pkgs.xinput}/bin/xinput set-prop "$id" \
          "Coordinate Transformation Matrix" $matrix || true
      done
    }

    current_rotation() {
      ${pkgs.xrandr}/bin/xrandr --query \
        | ${pkgs.gnugrep}/bin/grep -E '^DSI-1 connected' \
        | ${pkgs.gnugrep}/bin/grep -oE ' (normal|left|inverted|right) \(' \
        | ${pkgs.coreutils}/bin/tr -d ' ('
    }

    # xrandr omits the orientation word entirely when it is "normal".
    boot_rotation="$(current_rotation)"
    map_touchscreen "''${boot_rotation:-normal}"

    ${pkgs.iio-sensor-proxy}/bin/monitor-sensor 2>&1 \
      | grep --line-buffered "orientation" \
      | sed -u 's/.*orientation: //' \
      | while IFS= read -r orientation; do
          case "$orientation" in
            # The DSI panel is mounted 90 degrees clockwise relative to the
            # accelerometer, so every sensor orientation needs that offset.
            normal)    rotation=right ;;
            bottom-up) rotation=left ;;
            left-up)   rotation=normal ;;
            right-up)  rotation=inverted ;;
            *) continue ;;
          esac
          ${pkgs.xrandr}/bin/xrandr --output DSI-1 --rotate "$rotation"
          map_touchscreen "$rotation"
        done
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./custom-kernel.nix
    ../../profiles/base.nix
    ../../profiles/disk.nix
    ../../profiles/fabius-default.nix
    ../../profiles/programming.nix
    ../../profiles/usb_hub_dev.nix
    ../../profiles/claude.nix
  ];

  # ── Disk (Disko) ──────────────────────────────────────────────────────────────
  # Whole-disk LUKS (FIDO2/YubiKey + passphrase) layout from profiles/disk.nix,
  # applied to the 58GB eMMC. by-id basename of /dev/mmcblk0.
  local.disk.full_disk = {
    id = "mmc-HCG8e__0x1926946a";
    overProvisioning = "5G";  # leave 5GB unpartitioned for eMMC endurance
  };

  # ── Bootloader ────────────────────────────────────────────────────────────────
  # systemd-boot + EFI variable handling come from profiles/disk.nix.
  #
  # EFI variables ARE writable here: `efibootmgr -v` shows a firmware entry
  # Boot0001 "Linux Boot Manager" -> \EFI\systemd\systemd-bootx64.efi, first in
  # BootOrder, so the firmware honours a real NixOS entry and canTouchEfiVariables
  # is left at the disk.nix default of true.
  #
  # The generic fallback must still NOT be deleted: BootCurrent was 0000 ("EFI
  # Embedded MMC Device", the removable-media path), so the firmware does boot
  # via EFI/BOOT/BOOTX64.EFI in practice and disk.nix's removeGenericEfiFallback
  # would break that path.
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.timeout = lib.mkForce 1;
  system.activationScripts.removeGenericEfiFallback.text = lib.mkForce "";

  # Graphical initrd prompt for LUKS/FIDO2 unlock.
  boot.plymouth.enable = true;
  boot.plymouth.theme = "bgrt";

  # ── Kernel params ─────────────────────────────────────────────────────────────
  boot.kernelParams = [
    "zswap.enabled=0"
    "splash"
    "quiet"
    "udev.log_level=3"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "i915.enable_dpcd_backlight=0"
    "i915.force_probe=*"
    "panic=10"
    "softlockup_panic=1"
    "nmi_watchdog=panic"
    "hung_task_panic=1"
  ];

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "20s";
    RebootWatchdogSec  = "30s";
    KExecWatchdogSec   = "30s";
  };

  boot.kernel.sysctl = {
    "kernel.panic"               = lib.mkForce 10;
    "kernel.panic_on_oops"       = lib.mkForce 1;
    "kernel.softlockup_panic"    = lib.mkForce 1;
    "kernel.hardlockup_panic"    = lib.mkForce 1;
    "kernel.hung_task_panic"     = lib.mkForce 1;
    "kernel.hung_task_timeout_secs" = lib.mkForce 60;
    "kernel.panic_on_rcu_stall"  = lib.mkForce 1;
  };

  # axp288_charger polls I2C5 aggressively and causes repeated timeouts.
  boot.blacklistedKernelModules = [ "axp288_charger" ];

  # ── initrd ────────────────────────────────────────────────────────────────────
  # The custom MIIX kernel builds the boot-critical tablet drivers in directly:
  # eMMC/SDHCI, xHCI, USB HID, ext4, vfat, and CRC support.  Do not pull the
  # generic NixOS initrd module set; it includes unused SATA/NVMe modules such
  # as ahci, which this deliberately minimal kernel does not build.
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.initrd.kernelModules = lib.mkForce [ ];
  boot.kernelModules = lib.mkForce [ ];

  boot.initrd.extraFirmwarePaths = [
    "intel/fw_sst_22a8.bin"
    "regulatory.db"
    "regulatory.db.p7s"
  ];

  # ── Fast init handoff ─────────────────────────────────────────────────────────
  # Use nixos-init instead of the legacy initrd chroot prepare-root path.
  system.nixos-init.enable = true;
  system.etc.overlay.enable = true;
  services.userborn.enable = true;

  console.enable = lib.mkForce false;

  # ── base.nix overrides ────────────────────────────────────────────────────────
  security.pam.u2f.enable               = lib.mkForce false;

  # Allow wheel users to push store paths from the PC for remote deployment.
  # The remote builder entry below is only an offload target; the miix can still
  # build locally when workstation is absent or a derivation cannot be offloaded.
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "workstation";
        sshUser = "nixremote";
        sshKey = "/root/.ssh/nixremote-workstation";
        protocol = "ssh-ng";
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        maxJobs = 8;
        speedFactor = 4;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];

    settings = {
      trusted-users = [ "@wheel" ];
      builders-use-substitutes = true;
      max-jobs = "auto";
    };
  };

  # ── Firmware / GPU ────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # ── Accelerometer / auto-rotate ───────────────────────────────────────────────
  hardware.sensor.iio.enable = true;  # iio-sensor-proxy daemon

  # ── Power button ──────────────────────────────────────────────────────────────
  services.logind.settings.Login = {
    HandlePowerKey = "suspend";
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
  };

  # ── Battery ───────────────────────────────────────────────────────────────────
  services.upower.enable = true;

  # axp288_charger is blacklisted (I2C5 timeouts), so AC/charging state never
  # reaches userspace and the usual low-battery handling cannot fire. Poll the
  # fuel gauge directly instead and infer direction from current_now.
  systemd.user.services.battery-watch = {
    description = "Warn and suspend on low battery";
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = pkgs.writeShellScript "battery-watch" ''
      gauge=/sys/class/power_supply/axp288_fuel_gauge
      [ -r "$gauge/capacity" ] || exit 0
      capacity=$(${pkgs.coreutils}/bin/cat "$gauge/capacity")
      current=$(${pkgs.coreutils}/bin/cat "$gauge/current_now" 2>/dev/null || echo 0)

      # A positive current_now means the pack is charging; only act on drain.
      # Written as an if rather than `&& exit 0` because writeShellScript sets
      # -e, which would treat the false branch as a script failure.
      if [ "$current" -gt 0 ]; then
        exit 0
      fi

      if [ "$capacity" -le 5 ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical \
          "Battery critical" "$capacity% - suspending now"
        ${pkgs.systemd}/bin/systemctl suspend
      elif [ "$capacity" -le 15 ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical \
          "Battery low" "$capacity% remaining"
      fi
    '';
  };

  # Alacritty ships no NixOS module and no unit of its own, so the daemon is
  # defined here rather than exec'd from i3 -- systemd restarts it if it dies,
  # which an i3 `exec` (fired once at login) cannot do.
  systemd.user.services.alacritty-daemon = {
    description = "Alacritty terminal daemon";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.alacritty}/bin/alacritty --daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.timers.battery-watch = {
    description = "Periodic low-battery check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
  };

  # ── Thermal management ────────────────────────────────────────────────────────
  services.thermald.enable = true;

  # Keep the low-memory tablet responsive under memory pressure.
  services.earlyoom.enable = true;

  # ── DNS ───────────────────────────────────────────────────────────────────────
  services.resolved.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  # Wi-Fi stability: RTL8723BS uses the old r8723bs staging driver. Its
  # internal power-save modes and NetworkManager MAC randomization are both
  # fragile on this SDIO chip, especially after sustained traffic.
  networking.networkmanager.wifi.powersave = false;
  networking.networkmanager.settings = {
    device."wifi.scan-rand-mac-address" = "no";
    connection."wifi.cloned-mac-address" = "preserve";
  };

  boot.extraModprobeConfig = "options r8723bs rtw_power_mgnt=0 rtw_ips_mode=0 rtw_smart_ps=0 rtw_low_power=0 rtw_ht_enable=0 rtw_bw_mode=0";

  # ── Boot: don't block on network being online ─────────────────────────────────
  systemd.services.NetworkManager-wait-online.enable = false;

  # ── Audio ─────────────────────────────────────────────────────────────────────
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  # rt5645 codec sometimes misses its I2C probe window at boot due to bus
  # timing on Cherry Trail. This service re-binds it once the system is up.
  systemd.services.rt5645-reprobe = {
    description = "Re-probe rt5645 audio codec if initial probe failed";

    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "rt5645-reprobe" ''
        dev=/sys/bus/i2c/devices/i2c-10EC5645:00
        drv=/sys/bus/i2c/drivers/rt5645
        # Already probed successfully
        [ -e "$drv/i2c-10EC5645:00" ] && exit 0
        [ -e "$dev" ] || exit 0
        sleep 3
        echo "i2c-10EC5645:00" > "$drv/bind" 2>/dev/null || true
      '';
    };
  };

  systemd.timers.rt5645-reprobe = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "45s";
      AccuracySec = "5s";
      Unit = "rt5645-reprobe.service";
    };
  };

  # Nerd Fonts symbols used by the i3 status bar.
  fonts.packages = [
    pkgs.nerd-fonts.symbols-only
    pkgs.nerd-fonts.jetbrains-mono
  ];

  # ── i3 / X11 ──────────────────────────────────────────────────────────────────────
  services.xserver = {
    enable = true;
    xkb.layout = "de";
    autoRepeatDelay = repeat.delay;
    autoRepeatInterval = 1000 / repeat.rate;
    windowManager.i3.enable = true;
    displayManager.lightdm.enable = true;
    extraConfig = ''
      Section "Monitor"
        Identifier "DSI-1"
        Option "Rotate" "right"
      EndSection
    '';
  };

  services.displayManager = {
    defaultSession = "none+i3";
    autoLogin = {
      enable = true;
      user = config.local.primaryUser.name;
    };
  };

  programs.xss-lock.enable = true;

  # Touchpad feel. These are xf86-input-libinput InputClass options; the driver
  # defaults are noticeably twitchy on a pad this small.
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      tappingDragLock = true;
      naturalScrolling = true;
      scrollMethod = "twofinger";
      clickMethod = "clickfinger";
      disableWhileTyping = true;
      middleEmulation = true;
      accelProfile = "adaptive";
      accelSpeed = "0.3";
      # No dedicated NixOS option; the single biggest lever on scroll feel.
      additionalOptions = ''
        Option "ScrollPixelDistance" "35"
      '';
    };
  };

  # Without an authentication agent, pkexec and nm-applet's connection editor
  # fail silently. lxqt-policykit is used over polkit_gnome for closure size.
  security.polkit.enable = true;

  environment.systemPackages = with pkgs; [
    alacritty blueman brightnessctl dmenu dunst i3lock-color i3status-rust
    j4-dmenu-desktop libnotify lxqt.lxqt-policykit maim onboard pavucontrol
    rofi xclip xidlehook xinput xrandr
  ];


  # ── Status bar (i3status-rust, driving the native i3bar) ────────────────────
  #
  # axp288_charger is blacklisted, so there is no AC/mains supply for the bar to
  # read. The fuel gauge itself does report Charging/Discharging, so $percentage
  # plus the state icon are both usable; only "time to full/empty" is not.
  environment.etc."i3status-rust/config.toml".text = ''
    theme = "ctp-mocha"
    icons = "material-nf"

    [[block]]
    block = "focused_window"
    format = " $title.str(max_w:35) "

    [[block]]
    block = "music"
    format = " $icon $title.str(max_w:20) "
    [[block.click]]
    button = "left"
    action = "music_play_pause"

    [[block]]
    block = "net"
    format = " $icon $ssid|$device "
    missing_format = " $icon down "

    [[block]]
    block = "sound"
    format = " $icon $volume "
    [[block.click]]
    button = "left"
    cmd = "${pkgs.pavucontrol}/bin/pavucontrol"

    [[block]]
    block = "backlight"

    [[block]]
    block = "battery"
    device = "axp288_fuel_gauge"
    format = " $icon $percentage "
    full_format = " $icon $percentage "
    missing_format = " $icon x "
    warning = 25
    critical = 15

    [[block]]
    block = "memory"
    format = " $icon $mem_used_percents "

    [[block]]
    block = "disk_space"
    path = "/"
    format = " $icon $free "

    [[block]]
    block = "time"
    format = " $timestamp.datetime(f:'%Y-%m-%d %H:%M') "
    interval = 30
  '';

  # ── i3 config ───────────────────────────────────────────────────────────────
  #
  # NOTE: i3 prefers ~/.config/i3/config over this file. If that file exists it
  # silently shadows everything here, so it must stay absent on this host.
  environment.etc."i3/config".text = ''
    set $mod Mod1
    set $left h
    set $down j
    set $up k
    set $right l

    # Keep the i3 default terminal independent of the user's PATH. Windows are
    # created against a long-lived daemon so only the first launch pays the
    # cold-start cost; fall back to a plain instance if the daemon is gone.
    set $term ${terminalScript}
    # dmenu + j4 rather than rofi: a small Xlib binary with no theme engine or
    # icon loading, which is what actually costs time on cold eMMC. --usage-log
    # sorts by launch frequency.
    set $menu ${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop --dmenu='${pkgs.dmenu}/bin/dmenu -i -l 12 -fn "JetBrainsMono Nerd Font-11" -nb "#1e1e2e" -nf "#cdd6f4" -sb "#cba6f7" -sf "#1e1e2e"' --term-mode=alacritty --term=${pkgs.alacritty}/bin/alacritty --usage-log=/home/${config.local.primaryUser.name}/.cache/j4-usage.log

    font pango:JetBrainsMono Nerd Font 11
    client.focused #cba6f7 #cba6f7 #1e1e2e #cba6f7 #cba6f7
    client.unfocused #313244 #313244 #cdd6f4 #313244 #313244

    # Alt is left free for applications (Alt+w, Alt+f, ...); dragging floating
    # windows uses Super instead of grabbing Alt globally.
    floating_modifier Mod4 normal

    # ── Startup ─────────────────────────────────────────────────────────────────
    exec --no-startup-id ${pkgs.xsetroot}/bin/xsetroot -solid "#1e1e2e"
    exec --no-startup-id ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP
    exec --no-startup-id ${pkgs.dunst}/bin/dunst
    exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet
    exec --no-startup-id ${pkgs.blueman}/bin/blueman-applet
    exec --no-startup-id ${pkgs.lxqt.lxqt-policykit}/bin/lxqt-policykit-agent
    exec --no-startup-id ${autoRotateScript}
    exec --no-startup-id ${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.i3lock-color}/bin/i3lock -n -c 1e1e2e
    exec --no-startup-id ${pkgs.xidlehook}/bin/xidlehook --not-when-fullscreen --timer 120 '${pkgs.brightnessctl}/bin/brightnessctl set 20%' '${pkgs.brightnessctl}/bin/brightnessctl set 100%' --timer 180 '${pkgs.i3lock-color}/bin/i3lock -c 1e1e2e' true --timer 60 '${pkgs.xset}/bin/xset dpms force off' true

    # ── Launchers ───────────────────────────────────────────────────────────────
    bindsym $mod+Return exec $term
    bindsym $mod+d exec $menu
    bindsym $mod+o exec ${pkgs.onboard}/bin/onboard
    bindsym $mod+Shift+q kill

    # ── Focus ───────────────────────────────────────────────────────────────────
    # Arrows and hjkl move directionally; Tab and PgUp/PgDn walk the stack.
    bindsym $mod+$left  focus left
    bindsym $mod+$down  focus down
    bindsym $mod+$up    focus up
    bindsym $mod+$right focus right
    bindsym $mod+Left   focus left
    bindsym $mod+Down   focus down
    bindsym $mod+Up     focus up
    bindsym $mod+Right  focus right

    bindsym $mod+Tab       focus next
    bindsym $mod+Shift+Tab focus prev
    bindsym $mod+Prior     focus next sibling
    bindsym $mod+Next      focus prev sibling
    bindsym $mod+a         focus parent

    # ── Move ────────────────────────────────────────────────────────────────────
    bindsym $mod+Shift+$left  move left
    bindsym $mod+Shift+$down  move down
    bindsym $mod+Shift+$up    move up
    bindsym $mod+Shift+$right move right
    bindsym $mod+Shift+Left   move left
    bindsym $mod+Shift+Down   move down
    bindsym $mod+Shift+Up     move up
    bindsym $mod+Shift+Right  move right

    # ── Workspaces ──────────────────────────────────────────────────────────────
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9

    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9

    bindsym $mod+Control+Left  workspace prev
    bindsym $mod+Control+Right workspace next

    # ── Layout ──────────────────────────────────────────────────────────────────
    # $mod+w is intentionally left unbound so Alt+w reaches applications.
    bindsym $mod+b splith
    bindsym $mod+v splitv
    bindsym $mod+s layout stacking
    bindsym $mod+t layout tabbed
    bindsym $mod+e layout toggle split
    bindsym $mod+f fullscreen
    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space focus mode_toggle
    bindsym $mod+Shift+minus move scratchpad
    bindsym $mod+minus scratchpad show

    mode "resize" {
        bindsym $left  resize shrink width 10px
        bindsym $down  resize grow height 10px
        bindsym $up    resize shrink height 10px
        bindsym $right resize grow width 10px
        bindsym Left   resize shrink width 10px
        bindsym Down   resize grow height 10px
        bindsym Up     resize shrink height 10px
        bindsym Right  resize grow width 10px
        bindsym Return mode "default"
        bindsym Escape mode "default"
    }
    bindsym $mod+r mode "resize"

    # ── Media / hardware keys ───────────────────────────────────────────────────
    bindsym XF86AudioMute        exec ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle
    bindsym XF86AudioLowerVolume exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%
    bindsym XF86AudioRaiseVolume exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%
    bindsym XF86AudioMicMute     exec ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle
    bindsym XF86AudioPlay exec ${pkgs.playerctl}/bin/playerctl play-pause
    bindsym XF86AudioNext exec ${pkgs.playerctl}/bin/playerctl next
    bindsym XF86AudioPrev exec ${pkgs.playerctl}/bin/playerctl previous
    bindsym XF86MonBrightnessDown exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    bindsym XF86MonBrightnessUp   exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%+

    # ── Screenshots / notifications / session ───────────────────────────────────
    bindsym Print       exec ${pkgs.maim}/bin/maim -s | ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png
    bindsym Shift+Print exec ${pkgs.maim}/bin/maim | ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png

    bindsym $mod+n       exec ${pkgs.dunst}/bin/dunstctl close
    bindsym $mod+Shift+n exec ${pkgs.dunst}/bin/dunstctl history-pop

    bindsym $mod+Shift+x exec ${pkgs.i3lock-color}/bin/i3lock -c 1e1e2e
    bindsym $mod+Shift+e exec i3-msg exit
    bindsym $mod+Shift+r reload

    bar {
      position top
      font pango:JetBrainsMono Nerd Font 11
      status_command ${pkgs.i3status-rust}/bin/i3status-rs /etc/i3status-rust/config.toml
    }
  '';

  # ── Networking ────────────────────────────────────────────────────────────────
  networking.hostName = "miix310";

  # ── Bluetooth ─────────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # ── Locale extras (base.nix covers timezone and defaultLocale) ────────────────
  i18n.extraLocaleSettings.LC_TIME     = "de_DE.UTF-8";
  i18n.extraLocaleSettings.LC_MONETARY = "de_DE.UTF-8";

  # ── SSH ───────────────────────────────────────────────────────────────────────
  # The miix only needs outbound SSH to use workstation as a remote builder.
  services.openssh.enable = lib.mkForce false;
  services.printing.enable = true;

  # ── User extensions ───────────────────────────────────────────────────────────
  local.primaryUser.extraGroups = lib.mkAfter [ "input" "video" ];
  local.primaryUser.extraPackages = with pkgs; [
    firefox
    networkmanagerapplet
    playerctl
  ];

  system.stateVersion = "26.05";
}
