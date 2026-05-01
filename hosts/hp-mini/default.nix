{ config, pkgs, lib, ... }:
{
  networking.hostName = "hp-mini";

  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap = {
    enable    = true;
    algorithm = "zstd";
  };

  services.xserver = {
    enable = true;
    windowManager.openbox.enable = true;
  };

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    htop
    git
  ];

  system.stateVersion = "25.05";
}
