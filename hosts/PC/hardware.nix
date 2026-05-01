{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.systemd.enable = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [
    "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
    "usbhid" "hid_generic"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.initrd.luks.devices."cryptroot" = {
    device        = "/dev/disk/by-uuid/PLACEHOLDER";
    allowDiscards = true;
  };
}
