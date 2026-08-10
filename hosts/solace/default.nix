{ lib, pkgs, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/disk.nix
    ../../profiles/fabius-default.nix
    ../../profiles/programming.nix
    ../../profiles/claude.nix
  ];

  networking.hostName = "solace";

  local.disk.full_disk = {
    # TODO: replace before installing -- read the real name from
    # `ls -l /dev/disk/by-id` on the booted target. Disko destroys this device.
    id = "REPLACE-ME-mmc-XXXX";
    bootLayout = "raspberry-pi";
    overProvisioning = "16G";
  };

  hardware.raspberry-pi.firmware = {
    enable = true;
    path = "/boot";
    uboot.enable = true;
  };

  hardware.raspberry-pi.configtxt.settings.all = {
    avoid_warnings = true;
    hdmi_group = 1;
    hdmi_mode = 4;
    hdmi_force_mode = 1;
    hdmi_drive = 2;
    hdmi_pixel_encoding = 3;
    framebuffer_depth = 32;
    framebuffer_ignore_alpha = 1;
    framebuffer_swap = 0;
    disable_fw_kms_setup = lib.mkForce null;
    display_auto_detect = lib.mkForce null;
    dtoverlay = lib.mkForce null;
    dtparam = lib.mkForce null;
    max_framebuffers = lib.mkForce null;
    # enable_uart stays at the nixos-hardware default (true): U-Boot hangs on the
    # Pi 4 without it. Do not copy vesper's Pi-5 `enable_uart = false`.
  };
  hardware.enableRedistributableFirmware = true;

  boot.kernelParams = lib.mkForce [
    "console=tty0"
    "root=fstab"
    "loglevel=7"
    "systemd.show_status=1"
    "lsm=landlock,yama,bpf"
  ];

  # The raspberry-pi-4 module already sets boot.initrd.systemd.tpm2.enable = false.
  boot.initrd.kernelModules = [ "dm_mod" "mmc_block" ];

  local.primaryUser.extraPackages = with pkgs; [
    cryptsetup
    libraspberrypi
    lm_sensors
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  local.primaryUser.authorizedKeys = [
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDPgm7K7t41fVBh5Jajl4+vPyJO7jA45U8soik3sgL4kAAAACnNzaDpmYWJpdXM= fabius yubikey ssh"
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  system.stateVersion = "26.05";
}
