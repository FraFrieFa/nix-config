{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/fabius-default.nix
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/gaming.nix
    ../../profiles/programming.nix
    ../../profiles/signaged_dev.nix
    ../../profiles/unfree.nix
    ../../profiles/dabp.nix
  ];

  networking.hostName = "desktop";

  local.disk.full_disk = {
    id = "nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0X226913W";
    overProvisioning = "400G";
  };

  users.users.fabius.packages = with pkgs; [
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
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  boot.kernelModules = lib.mkForce [ "atkbd" "ctr" "loop" "uinput" ];

  system.stateVersion = "26.05";
}
