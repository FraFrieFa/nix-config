{ config, lib, pkgs, ... }:
let
  disk = config.local.disk.full_disk;
  rootPartition = {
    priority = 2;
    name = "cryptroot";
    label = "cryptroot";
    content = {
      type = "luks";
      name = "cryptroot";
      enrollFido2 = true;
      settings = {
        allowDiscards = true;
        bypassWorkqueues = true;
        crypttabExtraOpts = [
          "fido2-device=auto"
          "tries=0"
        ];
      };
      content = {
        type = "filesystem";
        format = "ext4";
        extraArgs = [ "-L" "NIXROOT" ];
        mountpoint = "/";
      };
    };
  } // lib.optionalAttrs (disk.overProvisioning != "0") {
    end = "-${disk.overProvisioning}";
  } // lib.optionalAttrs (disk.overProvisioning == "0") {
    size = "100%";
  };
in
{
  options.local.disk.full_disk = {
    id = lib.mkOption {
      type = lib.types.str;
      description = ''
        Stable /dev/disk/by-id basename for the whole system disk that Disko may
        partition and format during installation.
      '';
      example = "nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0T123456A";
    };

    overProvisioning = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "0" ]) (lib.types.strMatching "[0-9]+[KMGTP]");
      description = "Space left unpartitioned at the end of the disk.";
      example = "200G";
    };
  };

  config = {
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

    disko.devices.disk.system = {
      type = "disk";
      device = "/dev/disk/by-id/${disk.id}";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            name = "ESP";
            label = "boot";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = [ "-n" "BOOT" ];
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };

          cryptroot = rootPartition;
        };
      };
    };
  };
}
