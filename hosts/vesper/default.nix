{ lib, pkgs, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/disk.nix
    ../../profiles/fabius-default.nix
  ];

  networking.hostName = "vesper";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

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
  hardware.raspberry-pi.configtxt.settings.all = {
    avoid_warnings = true;
    "hdmi_group:0" = 1;
    "hdmi_mode:0" = 4;
    "hdmi_force_mode:0" = 1;
    "hdmi_drive:0" = 2;
    "hdmi_pixel_encoding:0" = 3;
    framebuffer_depth = 32;
    framebuffer_ignore_alpha = 1;
    framebuffer_swap = 0;
    disable_fw_kms_setup = lib.mkForce null;
    display_auto_detect = lib.mkForce null;
    dtoverlay = lib.mkForce null;
    dtparam = lib.mkForce null;
    max_framebuffers = lib.mkForce null;
  };
  hardware.enableRedistributableFirmware = true;

  boot.kernelParams = lib.mkForce [
    "console=tty0"
    "root=fstab"
    "loglevel=7"
    "systemd.show_status=1"
    "lsm=landlock,yama,bpf"
  ];

  boot.initrd.systemd.tpm2.enable = lib.mkForce false;
  boot.initrd.systemd.fido2.enable = true;
  boot.blacklistedKernelModules = [ "rp1_pio" ];
  boot.initrd.kernelModules = [ "dm_mod" "mmc_block" ];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "@wheel" ];
  };

  environment.systemPackages = with pkgs; [
    cryptsetup
    git
    htop
    jq
    kmod
    pciutils
    ripgrep
    usbutils
    vim
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

  users.users.fabius = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEo03wEt6WG7tfUdEsPVC9Zowg6Wizx6HJsDkki/dcYe fabius@desktop-to-10.55.0.2"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  system.stateVersion = "26.05";
}
