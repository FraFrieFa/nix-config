{ config, pkgs, lib, ... }:
{
  services.xserver = {
    enable     = true;
    xkb.layout = "de";
    autoRepeatDelay = 180;
    autoRepeatInterval = 20;
  };

  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
  ];

  xdg.portal = {
    config.common.default = "kde";
    extraPortals = lib.mkForce [
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
  };

  services.displayManager.sddm = {
    enable          = true;
    wayland.enable  = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "fabius";
  };
  services.displayManager.defaultSession = "plasmax11";

  programs.firefox = {
    enable = true;
    policies.ExtensionSettings = {
      "uBlock0@raymondhill.net" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        installation_mode = "normal_installed";
      };
    };
  };

  environment.etc."xdg/autostart/firefox.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Firefox
    Exec=${lib.getExe pkgs.firefox}
    Terminal=false
    X-GNOME-Autostart-enabled=true
    OnlyShowIn=KDE;
  '';

  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
  };
}
