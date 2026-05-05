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

  users.users.fabius.extraGroups = lib.mkAfter [ "gamemode" ];
}
