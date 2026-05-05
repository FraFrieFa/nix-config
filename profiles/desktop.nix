{ config, pkgs, lib, ... }:
{
  services.xserver = {
    enable     = true;
    xkb.layout = "de";
  };

  services.desktopManager.plasma6.enable = true;

  services.displayManager.sddm = {
    enable          = true;
    wayland.enable  = true;
  };

  programs.firefox = {
    enable = true;
    policies.ExtensionSettings = {
      "uBlock0@raymondhill.net" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        installation_mode = "normal_installed";
      };
    };
  };

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
