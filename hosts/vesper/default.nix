{ lib, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/fabius-default.nix
    ../../profiles/disk.nix
    ../../profiles/programming.nix
  ];

  networking.hostName = "vesper";
  networking.networkmanager.enable = lib.mkForce false;
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;
    networks."10-ethernet" = {
      matchConfig.Name = "end0 eth0";
      networkConfig.DHCP = "yes";
    };
  };
  networking.firewall.enable = true;

  local.disk.full_disk = {
    id = "mmc-SN512_0x7cc51f60";
    bootLayout = "raspberry-pi";
    overProvisioning = "48G";
  };

  # Populate the freshly formatted boot partition with the official Raspberry
  # Pi firmware, U-Boot, device trees, and config.txt on every activation.
  hardware.raspberry-pi.firmware = {
    enable = true;
    path = "/boot";
    uboot.enable = true;
  };

  boot.initrd.systemd.tpm2.enable = lib.mkForce false;

  system.stateVersion = "26.05";
}
