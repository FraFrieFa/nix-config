{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.systemd.enable = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Intel integrated graphics
  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # LUKS encrypted root - replace UUID after installation
  boot.initrd.luks.devices."cryptroot" = {
    device        = "/dev/disk/by-uuid/REPLACE-WITH-YOUR-LUKS-UUID";
    allowDiscards = true;
  };

  # Filesystems - replace UUIDs after installation
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-YOUR-EFI-UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
