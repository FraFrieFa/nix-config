{ config, pkgs, lib, ... }:
{
  boot.kernelParams = [
    "mitigations=auto"    # Keep security mitigations
    "nowatchdog"          # Reduce latency spikes
    "nmi_watchdog=0"
    "tsc=reliable"        # Stable timestamps for games
  ];

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "kernel.sched_autogroup_enabled" = 1;
  };

  security.rtkit.enable = true;

  programs.steam.enable = true;
}
