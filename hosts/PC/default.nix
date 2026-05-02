{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/gaming.nix
  ];

  networking.hostName = "PC";

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

  system.stateVersion = "26.05";
}
