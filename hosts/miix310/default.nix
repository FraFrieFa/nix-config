{ config, lib, pkgs, ... }:
let
  repeat = config.local.keyboard.repeat;

  autoRotateScript = pkgs.writeShellScript "auto-rotate" ''
    # Wait for X and i3 to be ready.
    sleep 2

    map_touchscreen() {
      ${pkgs.xorg.xinput}/bin/xinput list --name-only \
        | ${pkgs.gnugrep}/bin/grep -Ei 'touchscreen|FTSC1000' \
        | while IFS= read -r device; do
            ${pkgs.xorg.xinput}/bin/xinput map-to-output "$device" DSI-1 || true
          done
    }

    map_touchscreen
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
          ${pkgs.xorg.xrandr}/bin/xrandr --output DSI-1 --rotate "$rotation"
          map_touchscreen
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
  # systemd-boot + EFI handling come from profiles/disk.nix. Two host overrides:
  # this INSYDE/Cherry Trail firmware boots ONLY the removable-media fallback
  # EFI/BOOT/BOOTX64.EFI (confirmed via `bootctl`) and the efivars-brick risk on
  # this hardware class means we do NOT write EFI variables, and must NOT delete
  # that fallback binary (disk.nix's removeGenericEfiFallback would brick boot).
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
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
  services.logind.settings.Login.HandlePowerKey = "suspend";

  # ── Battery ───────────────────────────────────────────────────────────────────
  services.upower.enable = true;

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
  fonts.packages = [ pkgs.nerd-fonts.symbols-only ];

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

  environment.systemPackages = with pkgs; [
    alacritty brightnessctl dunst i3lock-color i3status maim onboard
    pavucontrol rofi xclip xidlehook xorg.xinput xorg.xrandr
  ];


  # ── i3status and i3 config ───────────────────────────────────────────────────────────────
  environment.etc."i3status.conf".text = ''
    general {
      colors = true
      interval = 5
    }
    order += "wireless _first_"
    order += "battery all"
    order += "disk /"
    order += "memory"
    order += "volume master"
    order += "tztime local"

    wireless _first_ {
      format_up = "W: %essid"
      format_down = "W: offline"
    }
    battery all {
      format = "%status %percentage"
      format_down = "No battery"
      status_chr = "CHR"
      status_bat = "BAT"
      status_unk = "UNK"
      low_threshold = 15
    }
    disk "/" {
      format = "%avail free"
    }
    memory {
      format = "%available free"
    }
    volume master {
      format = "Vol: %volume"
      format_muted = "Vol: muted"
      device = "pulse"
    }
    tztime local {
      format = "%Y-%m-%d %H:%M"
    }
  '';

  # ── i3 config ───────────────────────────────────────────────────────────────────────────────
  environment.etc."i3/config".text = ''
    set $mod Mod1
    set $left h
    set $down j
    set $up k
    set $right l
    # Keep the i3 default terminal independent of the user's PATH.
    set $term ${pkgs.alacritty}/bin/alacritty
    set $menu ${pkgs.rofi}/bin/rofi -show drun

    font pango:Noto Sans 12
    client.focused #cba6f7 #cba6f7 #1e1e2e #cba6f7 #cba6f7
    client.unfocused #313244 #313244 #cdd6f4 #313244 #313244

    # ── Startup ──────────────────────────────────────────────────────────────────
    exec --no-startup-id ${pkgs.xorg.xsetroot}/bin/xsetroot -solid "#1e1e2e"
    exec --no-startup-id ${pkgs.dunst}/bin/dunst
    exec --no-startup-id ${pkgs.networkmanagerapplet}/bin/nm-applet
    exec --no-startup-id ${autoRotateScript}
    exec --no-startup-id ${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.i3lock-color}/bin/i3lock -n -c 1e1e2e
    exec --no-startup-id ${pkgs.xidlehook}/bin/xidlehook --not-when-fullscreen --timer 120 '${pkgs.brightnessctl}/bin/brightnessctl set 20%' '${pkgs.brightnessctl}/bin/brightnessctl set 100%' --timer 180 '${pkgs.i3lock-color}/bin/i3lock -c 1e1e2e' true --timer 60 '${pkgs.xorg.xset}/bin/xset dpms force off' true

    # ── Bindings ─────────────────────────────────────────────────────────────────
    bindsym $mod+Return exec $term
    bindsym $mod+Shift+q kill
    bindsym $mod+d exec $menu
    bindsym $mod+o exec ${pkgs.onboard}/bin/onboard  # on-screen keyboard
    floating_modifier $mod normal

    bindsym $mod+$left  focus left
    bindsym $mod+$down  focus down
    bindsym $mod+$up    focus up
    bindsym $mod+$right focus right
    bindsym $mod+Left   focus left
    bindsym $mod+Down   focus down
    bindsym $mod+Up     focus up
    bindsym $mod+Right  focus right

    bindsym $mod+Shift+$left  move left
    bindsym $mod+Shift+$down  move down
    bindsym $mod+Shift+$up    move up
    bindsym $mod+Shift+$right move right
    bindsym $mod+Shift+Left   move left
    bindsym $mod+Shift+Down   move down
    bindsym $mod+Shift+Up     move up
    bindsym $mod+Shift+Right  move right

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

    bindsym $mod+b splith
    bindsym $mod+v splitv
    bindsym $mod+e layout toggle split
    bindsym $mod+f fullscreen
    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space focus mode_toggle
    bindsym $mod+a focus parent
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

    bindsym XF86AudioMute        exec pactl set-sink-mute @DEFAULT_SINK@ toggle
    bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
    bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
    bindsym XF86AudioMicMute     exec pactl set-source-mute @DEFAULT_SOURCE@ toggle
    bindsym XF86MonBrightnessDown exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    bindsym XF86MonBrightnessUp   exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%+
    bindsym Print exec ${pkgs.maim}/bin/maim -s | ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png

    bindsym $mod+Shift+e exec i3-msg exit
    bindsym $mod+Shift+r reload

    bar {
      position top
      status_command ${pkgs.i3status}/bin/i3status --config /etc/i3status.conf
    }
  '';

  # ── Networking ────────────────────────────────────────────────────────────────
  networking.hostName = "miix310";

  # ── Bluetooth ─────────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
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
