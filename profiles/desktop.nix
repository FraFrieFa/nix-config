{ config, pkgs, lib, ... }:
let
  repeat = config.local.keyboard.repeat;
  repeatInterval = 1000 / repeat.rate;

  disableKWinTopLeftHotCorner = pkgs.writeShellScript "disable-kwin-top-left-hot-corner" ''
    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrc --group ElectricBorders --key TopLeft None
    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrc --group Effect-overview --key BorderActivate ""
    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrc --group Effect-overview --key TouchBorderActivate ""
    ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  '';
in
{
  services.xserver = {
    enable     = true;
    xkb.layout = "de";
    autoRepeatDelay = repeat.delay;
    autoRepeatInterval = repeatInterval;
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

  services.fwupd.enable = false;

  programs.kclock.enable = true;

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

  environment.etc."xdg/kwinrc".text = ''
    [ElectricBorders]
    TopLeft=None

    [Effect-overview]
    BorderActivate=
    TouchBorderActivate=
  '';

  environment.etc."xdg/autostart/disable-kwin-top-left-hot-corner.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Disable KWin Top Left Hot Corner
    Exec=${disableKWinTopLeftHotCorner}
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
