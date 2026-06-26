{ config, lib, pkgs, ... }:
let
  autoRotateScript = pkgs.writeShellScript "auto-rotate" ''
    # Wait for sway to be ready
    sleep 2
    ${pkgs.iio-sensor-proxy}/bin/monitor-sensor 2>&1 \
      | grep --line-buffered "orientation" \
      | sed -u 's/.*orientation: //' \
      | while IFS= read -r orientation; do
          case "$orientation" in
            normal)    ${pkgs.sway}/bin/swaymsg output DSI-1 transform normal ;;
            bottom-up) ${pkgs.sway}/bin/swaymsg output DSI-1 transform 180 ;;
            left-up)   ${pkgs.sway}/bin/swaymsg output DSI-1 transform 270 ;;
            right-up)  ${pkgs.sway}/bin/swaymsg output DSI-1 transform 90 ;;
          esac
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
  boot.kernel.sysctl."kernel.dmesg_restrict" = lib.mkForce 0;
  security.pam.u2f.enable               = lib.mkForce false;

  # Allow wheel users to push store paths from the PC for remote deployment
  nix.settings.trusted-users = [ "root" "@wheel" ];

  # ── Firmware / GPU ────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # ── Accelerometer / auto-rotate ───────────────────────────────────────────────
  hardware.sensor.iio.enable = true;  # iio-sensor-proxy daemon

  # ── Battery ───────────────────────────────────────────────────────────────────
  services.upower.enable = true;

  # ── Thermal management ────────────────────────────────────────────────────────
  services.thermald.enable = true;

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

  networking.firewall.enable = lib.mkForce false;

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

  # ── Sway ──────────────────────────────────────────────────────────────────────
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swayidle swaybg
      waybar foot fuzzel
      grim slurp wl-clipboard
      mako brightnessctl pavucontrol
      wvkbd          # on-screen keyboard
      wl-mirror      # screen cast helper
    ];
  };

  systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";

  services.greetd = {
    enable = true;
    settings = {
      terminal.vt = 1;
      default_session = {
        command = "${pkgs.dbus}/bin/dbus-run-session ${pkgs.sway}/bin/sway";
        user = "fabius";
      };
    };
  };

  # ── Waybar ────────────────────────────────────────────────────────────────────
  environment.etc."xdg/waybar/config".text = builtins.toJSON {
    layer    = "top";
    position = "top";
    height   = 36;
    modules-left   = [ "sway/workspaces" "sway/mode" ];
    modules-center = [ "clock" ];
    modules-right  = [ "battery" "backlight" "pulseaudio" "network" ];

    "sway/workspaces" = { disable-scroll = true; };
    "sway/mode"       = { format = "<span style='italic'>{}</span>"; };

    clock = { format = "  {:%Y-%m-%d  %H:%M}"; tooltip = false; };

    battery = {
      format          = "{icon}  {capacity}%";
      format-charging = "  {capacity}%";
      format-icons    = [ "" "" "" "" "" ];
      states          = { warning = 30; critical = 15; };
      tooltip         = false;
    };

    backlight = {
      device         = "intel_backlight";
      format         = "  {percent}%";
      on-scroll-up   = "${pkgs.brightnessctl}/bin/brightnessctl set 5%+";
      on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
      tooltip        = false;
    };

    pulseaudio = {
      format        = "{icon}  {volume}%";
      format-muted  = "  muted";
      format-icons  = { default = [ "" "" "" ]; };
      on-click      = "${pkgs.pavucontrol}/bin/pavucontrol";
      tooltip       = false;
    };

    network = {
      format-wifi         = "  {essid}";
      format-disconnected = "  offline";
      tooltip             = false;
    };
  };

  environment.etc."xdg/waybar/style.css".text = ''
    * {
      font-family: "Noto Sans", monospace;
      font-size: 14px;
      min-height: 0;
    }
    window#waybar {
      background: rgba(30, 30, 46, 0.92);
      color: #cdd6f4;
      border-bottom: 2px solid #313244;
    }
    #workspaces button {
      padding: 0 8px;
      color: #6c7086;
      background: transparent;
      border: none;
    }
    #workspaces button.focused, #workspaces button.active {
      color: #cba6f7;
    }
    #clock, #battery, #backlight, #pulseaudio, #network, #mode {
      padding: 0 12px;
    }
    #battery.warning  { color: #fab387; }
    #battery.critical { color: #f38ba8; }
    #mode { background: #cba6f7; color: #1e1e2e; }
  '';

  # ── Sway config ───────────────────────────────────────────────────────────────
  environment.etc."sway/config".text = ''
    set $mod Mod1
    set $left h
    set $down j
    set $up k
    set $right l
    set $term foot
    set $menu fuzzel --show run --no-icons

    output DSI-1 bg #1e1e2e solid_color

    input type:keyboard {
        xkb_layout "de"
        repeat_delay 250
        repeat_rate  40
    }

    input type:touchscreen {
        tap enabled
        map_to_output DSI-1
    }

    # ── Startup ──────────────────────────────────────────────────────────────────
    exec waybar
    exec mako
    exec exec ${autoRotateScript}
    exec swayidle -w \
        timeout 120 '${pkgs.brightnessctl}/bin/brightnessctl set 20%' \
        resume  '${pkgs.brightnessctl}/bin/brightnessctl set 100%' \
        before-sleep '${pkgs.brightnessctl}/bin/brightnessctl set 20%'

    # ── Bindings ─────────────────────────────────────────────────────────────────
    bindsym $mod+Return exec $term
    bindsym $mod+Shift+q kill
    bindsym $mod+d exec $menu
    bindsym $mod+o exec ${pkgs.wvkbd}/bin/wvkbd-mobintl  # on-screen keyboard
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

    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5

    bindsym $mod+b splith
    bindsym $mod+v splitv
    bindsym $mod+s layout stacking
    bindsym $mod+w layout tabbed
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

    bindsym --locked XF86AudioMute        exec pactl set-sink-mute @DEFAULT_SINK@ toggle
    bindsym --locked XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
    bindsym --locked XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
    bindsym --locked XF86AudioMicMute     exec pactl set-source-mute @DEFAULT_SOURCE@ toggle
    bindsym --locked XF86MonBrightnessDown exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    bindsym --locked XF86MonBrightnessUp   exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%+
    bindsym Print exec ${pkgs.grim}/bin/grim

    bindsym $mod+Shift+e exec swaymsg exit
    bindsym $mod+Shift+r reload

    include /etc/sway/config.d/*
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
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # ── User extensions ───────────────────────────────────────────────────────────
  users.users.fabius.extraGroups = lib.mkAfter [ "input" "video" ];
  users.users.fabius.initialPassword = "nixos";
  users.users.fabius.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDY1Ph0sLtoppnck/L1R6PhstsqllBh3pI/cJcGwI7U/ lenovo-miix310"
  ];
  users.users.fabius.packages = with pkgs; [
    firefox
    networkmanagerapplet
    playerctl
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
