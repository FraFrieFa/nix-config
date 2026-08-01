{ config, lib, pkgs, ... }:
let
  disk = config.local.disk.full_disk;

  isPercentage = lib.hasSuffix "%" disk.overProvisioning;
  overProvisioningPercent =
    builtins.fromJSON (lib.removeSuffix "%" disk.overProvisioning);

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
    name = if disk.encryption == "luks" then "cryptroot" else "root";
    label = if disk.encryption == "luks" then "cryptroot" else "root";
    content = if disk.encryption == "luks" then encryptedRoot else rootFilesystem;
  } // lib.optionalAttrs isPercentage {
    end = "${toString (100 - overProvisioningPercent)}%";
  } // lib.optionalAttrs (!isPercentage && disk.overProvisioning != "0") {
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
    ${if disk.encryption == "luks" then "cryptroot" else "root"} = rootPartition;
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

    encryption = lib.mkOption {
      type = lib.types.enum [ "luks" "none" ];
      default = "luks";
      description = "Encryption used for the root filesystem.";
    };

    overProvisioning = lib.mkOption {
      type = lib.types.oneOf [
        (lib.types.enum [ "0" ])
        (lib.types.strMatching "[0-9]+[KMGTP]")
        (lib.types.strMatching "([1-9]|[1-9][0-9])%")
      ];
      description = "Space or percentage left unpartitioned at the end of the disk.";
      example = "20%";
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

    (lib.mkIf (disk.encryption == "luks") {
      boot.initrd.systemd.enable = true;
      boot.initrd.systemd.fido2.enable = true;
      boot.initrd.systemd.storePaths = [
        "${pkgs.pcsclite.lib}/lib/libpcsclite_real.so.1"
      ];
    })

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
