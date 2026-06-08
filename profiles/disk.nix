{ lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 0;

  system.activationScripts.removeGenericEfiFallback.text = ''
    ${pkgs.coreutils}/bin/rm -f /boot/EFI/BOOT/BOOTX64.EFI
  '';

  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.fido2.enable = true;
  boot.initrd.systemd.storePaths = [
    "${pkgs.pcsclite.lib}/lib/libpcsclite_real.so.1"
  ];

  boot.initrd.luks.devices."cryptroot" = {
    device           = "/dev/disk/by-partlabel/cryptroot";
    allowDiscards    = true;
    bypassWorkqueues = true;
    crypttabExtraOpts = [
      "fido2-device=auto"
      "tries=0"
    ];
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
