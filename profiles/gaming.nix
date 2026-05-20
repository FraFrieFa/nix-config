{ config, pkgs, lib, ... }:
let
  dota2 = pkgs.writeShellApplication {
    name = "dota2";
    runtimeInputs = [
      pkgs.gamemode
      pkgs.steam
    ];
    text = ''
      exec gamemoderun steam -applaunch 570 -vulkan -novid -sdlaudiodriver pulse
    '';
  };

  dota2DesktopItem = pkgs.makeDesktopItem {
    name = "dota2";
    desktopName = "Dota 2 (Nix Optimized)";
    comment = "Launch Dota 2 through Steam with GameMode and Vulkan";
    exec = "${dota2}/bin/dota2";
    icon = "steam_icon_570";
    categories = [ "Game" ];
  };
in
{

  boot.kernelParams = [
    "mitigations=auto"
    "nowatchdog"
    "nmi_watchdog=0"
    "preempt=full"
    "tsc=reliable"
  ];

  boot.kernel.sysctl = {
    "vm.swappiness"                  = 10;
    "vm.vfs_cache_pressure"          = 50;
    "kernel.sched_autogroup_enabled" = 1;
  };

  security.rtkit.enable = true;

  services.xserver.windowManager.openbox.enable = true;

  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        desiredgov = "performance";
        softrealtime = "auto";
        renice = 10;
        ioprio = 0;
        inhibit_screensaver = 1;
        disable_splitlock = 1;
      };

      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
        nv_powermizer_mode = 1;
      };
    };
  };

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    protontricks.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  environment.systemPackages = with pkgs; [
    dota2
    dota2DesktopItem
    gamescope
    goverlay
    libva-utils
    mangohud
    mesa-demos
    nvtopPackages.nvidia
    protontricks
    protonup-qt
    vulkan-tools
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    let
      name = pkgs.lib.getName pkg;
      licenses = pkgs.lib.toList (pkg.meta.license or []);
      hasCudaEula = pkgs.lib.any (license: (license.shortName or "") == "CUDA EULA") licenses;
    in
      hasCudaEula || pkgs.lib.any (prefix: pkgs.lib.hasPrefix prefix name) [
        "libnvidia"
        "nvidia"
      ] || builtins.elem name [
        "proton-ge-bin"
        "steam"
        "steam-original"
        "steam-unwrapped"
        "steam-run"
      ];

  users.users.fabius.extraGroups = lib.mkAfter [ "gamemode" ];
}
