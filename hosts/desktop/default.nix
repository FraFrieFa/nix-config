{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/gaming.nix
    ../../profiles/programming.nix
    ../../profiles/signaged_dev.nix
    ../../profiles/unfree.nix
  ];

  networking.hostName = "desktop";

  environment.systemPackages = with pkgs; [
    libfido2
    yubikey-manager
  ];

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  system.stateVersion = "26.05";
}
