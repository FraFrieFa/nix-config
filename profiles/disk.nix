{ lib, ... }:
{
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."cryptroot" = {
    device           = "/dev/disk/by-partlabel/cryptroot";
    allowDiscards    = true;
    bypassWorkqueues = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device  = "/dev/disk/by-label/BOOT";
    fsType  = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };
}
