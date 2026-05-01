{ config, pkgs, lib, ... }:
{
  networking.hostName = "PC";

  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap = {
    enable    = true;
    algorithm = "zstd";
  };

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open               = false;
    package            = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
  };

  services.xserver = {
    enable = true;
    windowManager.openbox.enable = true;
  };

  programs.steam.enable = true;

  programs.gamemode.enable = true;
  users.users.fabius.extraGroups = lib.mkAfter [ "gamemode" ];

  system.stateVersion = "25.05";
}
