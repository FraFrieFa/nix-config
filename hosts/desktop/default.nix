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

  networking.hostName = "desktop";

  local.disk.full_disk = {
    id = "nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0X226913W";
    overProvisioning = "400G";
  };

  local.primaryUser.extraPackages = with pkgs; [
    ddcutil
  ];

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.i2c.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  boot.kernelParams = [
    "nvidia.NVreg_TemporaryFilePath=/var/tmp"
  ];

  services.logind.settings.Login = {
    HandlePowerKey = "poweroff";
    PowerKeyIgnoreInhibited = true;
  };

  boot.kernelModules = lib.mkForce [ "atkbd" "ctr" "i2c-dev" "loop" "uinput" ];

  system.stateVersion = "26.05";
}
