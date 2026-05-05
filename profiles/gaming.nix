{ config, pkgs, lib, ... }:
{
  boot.kernelParams = [
    "mitigations=auto"
    "nowatchdog"
    "nmi_watchdog=0"
    "tsc=reliable"
  ];

  boot.kernel.sysctl = {
    "vm.swappiness"                  = 10;
    "vm.vfs_cache_pressure"          = 50;
    "kernel.sched_autogroup_enabled" = 1;
  };

  security.rtkit.enable = true;

  services.xserver.windowManager.openbox.enable = true;

  programs.gamemode.enable = true;

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  environment.systemPackages = with pkgs; [
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
