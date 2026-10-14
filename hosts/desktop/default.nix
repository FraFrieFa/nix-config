{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/fabius-default.nix
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/gaming.nix
    ../../profiles/programming.nix
    ../../profiles/claude.nix
    ../../profiles/unfree.nix
    ../../profiles/usb_hub_dev.nix
    ../../profiles/hs80-max.nix
  ];

  # The one host with a screen to watch the browser on.
  local.playwright.headless = false;

  networking.hostName = "desktop";

  local.disk.full_disk = {
    id = "nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0X226913W";
    overProvisioning = "400G";
  };

  local.primaryUser.extraPackages = with pkgs; [
    ddcutil
  ];

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      qt6Packages.fcitx5-chinese-addons
      fcitx5-gtk
      kdePackages.fcitx5-qt
    ];
  };

  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.i2c.enable = true;

  services.printing.enable = true;
  services.printing.drivers = [ pkgs.hplip ];

  hardware.sane.enable = true;
  hardware.sane.extraBackends = [ pkgs.hplip ];
  local.primaryUser.extraGroups = lib.mkAfter [ "scanner" "lp" ];

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  boot.kernelParams = [
    "nvidia.NVreg_TemporaryFilePath=/var/tmp"
    "pcie_port_pm=off"
    "panic=10"
    "softlockup_panic=1"
    "hung_task_panic=1"
    "hung_task_timeout_secs=30"
  ];

  boot.consoleLogLevel = 7;

  systemd.settings.Manager.RebootWatchdogSec = "60s";

  systemd.services.systemd-pstore.wantedBy = [ "sysinit.target" ];

  services.logind.settings.Login = {
    HandlePowerKey = "poweroff";
    PowerKeyIgnoreInhibited = true;
  };

  boot.kernelModules = lib.mkForce [ "atkbd" "ctr" "efi_pstore" "i2c-dev" "loop" "uinput" ];

  system.stateVersion = "26.05";
}
