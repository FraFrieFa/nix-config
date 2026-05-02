{ config, pkgs, lib, ... }:
{
  services.xserver = {
    enable     = true;
    xkb.layout = "de";
    desktopManager.xfce.enable = true;
  };

  services.xserver.displayManager.lightdm.enable = true;

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    htop
    git
  ];

  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
  };
}
