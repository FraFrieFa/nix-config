{ config, lib, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # ── Bootloader ────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = false;  # shared EFI partition with CachyOS

  # ── Kernel params ─────────────────────────────────────────────────────────────
  boot.kernelParams = [
    "zswap.enabled=0"
    "nowatchdog"
    "loglevel=8"
    "video=DSI-1:800x1280@60,rotate=90"
    "i915.enable_dpcd_backlight=0"
    "i915.force_probe=*"
    "i915.mipi_backlight=2"
  ];

  # ── initrd ────────────────────────────────────────────────────────────────────
  # i915 must stay out of initrd — loading it early breaks display stride
  boot.initrd.kernelModules = [ "mmc_block" "crc32c" ];

  # ── Firmware ──────────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # ── GPU ───────────────────────────────────────────────────────────────────────
  hardware.graphics.enable = true;

  # ── Sway ──────────────────────────────────────────────────────────────────────
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock swayidle swaybg
      waybar foot fuzzel alacritty wofi
      grim slurp wl-clipboard
      mako brightnessctl pavucontrol
    ];
  };

  services.greetd = {
    enable = true;
    settings = {
      terminal.vt = 1;
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "greeter";
      };
    };
  };

  environment.etc."sway/config".text = ''
    set $mod Mod1
    set $left h
    set $down j
    set $up k
    set $right l
    set $term foot
    set $menu fuzzel --show run --no-icons

    output * bg #1a1a2e solid_color

    input type:keyboard {
        xkb_layout "de"
    }

    input type:touchscreen {
        tap enabled
        map_to_output DSI-1
    }

    bindsym $mod+Return exec $term
    bindsym $mod+Shift+q kill
    bindsym $mod+d exec $menu
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
    bindsym $mod+0 workspace number 10

    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9
    bindsym $mod+Shift+0 move container to workspace number 10

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
    bindsym --locked XF86MonBrightnessDown exec brightnessctl set 5%-
    bindsym --locked XF86MonBrightnessUp   exec brightnessctl set 5%+
    bindsym Print exec grim

    bindsym $mod+Shift+e exec swaymsg exit
    bindsym $mod+Shift+r reload

    bar {
        position top
        status_command while :; do date +"  %Y-%m-%d  %H:%M:%S"; sleep 1; done
        colors {
            statusline #ffffff
            background #323232
            inactive_workspace #32323200 #32323200 #5c5c5c
        }
    }

    include /etc/sway/config.d/*
  '';

  # ── Networking ────────────────────────────────────────────────────────────────
  networking.hostName = "miix310";
  networking.networkmanager.enable = true;

  # ── Bluetooth ─────────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # ── Audio ─────────────────────────────────────────────────────────────────────
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ── Time / locale ─────────────────────────────────────────────────────────────
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings.LC_TIME     = "de_DE.UTF-8";
  i18n.extraLocaleSettings.LC_MONETARY = "de_DE.UTF-8";
  console.keyMap = "de";

  # ── SSH ───────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # ── Sudo ──────────────────────────────────────────────────────────────────────
  security.sudo.wheelNeedsPassword = false;

  # ── Nix ───────────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── User ──────────────────────────────────────────────────────────────────────
  users.users.fabius = {
    isNormalUser = true;
    description  = "Fabius";
    extraGroups  = [ "wheel" "networkmanager" "audio" "video" "input" ];
    shell        = pkgs.bash;
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDY1Ph0sLtoppnck/L1R6PhstsqllBh3pI/cJcGwI7U/ lenovo-miix310"
    ];
  };

  # ── Packages ──────────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim git wget curl htop
    firefox networkmanagerapplet
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
