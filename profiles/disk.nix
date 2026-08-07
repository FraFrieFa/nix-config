{ config, lib, pkgs, ... }:
let
  disk = config.local.disk.full_disk;

  rootFilesystem = {
    type = "filesystem";
    format = "ext4";
    extraArgs = [ "-L" "NIXROOT" ];
    mountpoint = "/";
  };

  encryptedRoot = {
    type = "luks";
    name = "cryptroot";
    enrollFido2 = true;
    extraFido2EnrollArgs = [ "--fido2-with-client-pin=no" ];
    askPassword = true;
    settings = {
      allowDiscards = true;
      bypassWorkqueues = true;
      crypttabExtraOpts = [
        "fido2-device=auto"
        "tries=0"
      ];
    };
    content = rootFilesystem;
  };

  rootPartition = {
    priority = 2;
    name = "cryptroot";
    label = "cryptroot";
    content = encryptedRoot;
  } // lib.optionalAttrs (disk.overProvisioning != "0") {
    end = "-${disk.overProvisioning}";
  } // lib.optionalAttrs (disk.overProvisioning == "0") {
    size = "100%";
  };

  isRaspberryPi = disk.bootLayout == "raspberry-pi";
  bootPartition = {
    priority = 1;
    name = if isRaspberryPi then "firmware" else "ESP";
    label = if isRaspberryPi then "FIRMWARE" else "boot";
    size = "1G";
    type = "EF00";
    content = {
      type = "filesystem";
      format = "vfat";
      extraArgs = [ "-n" (if isRaspberryPi then "FIRMWARE" else "BOOT") ];
      mountpoint = "/boot";
      mountOptions = [ "fmask=0077" "dmask=0077" ];
    };
  };

  partitions = {
    cryptroot = rootPartition;
  } // (if isRaspberryPi then {
    firmware = bootPartition;
  } else {
    ESP = bootPartition;
  });
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

    bootLayout = lib.mkOption {
      type = lib.types.enum [ "uefi" "raspberry-pi" ];
      default = "uefi";
      description = "Boot partition and loader layout used by this host.";
    };

    overProvisioning = lib.mkOption {
      type = lib.types.oneOf [
        (lib.types.enum [ "0" ])
        (lib.types.strMatching "[0-9]+[KMGTP]")
      ];
      description = "Fixed-size space left unpartitioned at the end of the disk.";
      example = "20G";
    };
  };

  config = lib.mkMerge [
    {
      disko.devices.disk.system = {
        type = "disk";
        device = "/dev/disk/by-id/${disk.id}";
        content = {
          type = "gpt";
          inherit partitions;
        };
      };
    }

    {
      boot.initrd.systemd.enable = true;
      boot.initrd.systemd.fido2.enable = true;
    }

    (lib.mkIf (disk.bootLayout == "uefi") {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.timeout = 0;

      system.activationScripts.removeGenericEfiFallback.text = ''
        ${pkgs.coreutils}/bin/rm -f /boot/EFI/BOOT/BOOTX64.EFI
      '';
    })
  ];
}
