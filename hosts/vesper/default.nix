{ lib, pkgs, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/disk.nix
    ../../profiles/fabius-default.nix
    ../../profiles/programming.nix
    ../../profiles/claude.nix
    ../../profiles/screenpuck_dev.nix
  ];

  networking.hostName = "vesper";

  # No NAT relay here yet: vesper's uplink is end0/wld0, not the workstation's
  # enp0s31f6. Set this once it should hand internet to an attached gadget Pi.
  local.screenpuck.externalInterface = null;

  local.disk.full_disk = {
    id = "mmc-SN512_0x7cc51f60";
    bootLayout = "raspberry-pi";
    overProvisioning = "48G";
  };

  hardware.raspberry-pi.firmware = {
    enable = true;
    path = "/boot";
    uboot = {
      enable = true;
      # rpi_arm64_defconfig targets the Pi 4 and builds no driver that binds the
      # Pi 5's USB. On this board every port hangs off the RP1 southbridge behind
      # PCIe and is described in the DTB as bare `compatible = "snps,dwc3"`;
      # stock U-Boot enumerates the PCIe link fine but has nothing to attach, so
      # `usb start` reports "no USB controller found". xhci-dwc3 is the only
      # driver in-tree matching bare "snps,dwc3" (dwc3-generic matches vendor
      # glue compatibles only, none of which the Pi 5 uses).
      package = pkgs.ubootRaspberryPiAarch64.override {
        extraConfig = ''
          CONFIG_USB_XHCI_DWC3=y
        '';
      };
    };
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
  boot.blacklistedKernelModules = [ "rp1_pio" ];
  boot.initrd.kernelModules = [ "dm_mod" "mmc_block" ];

  # git/htop/jq/pciutils/ripgrep/usbutils come from the base primary-user set.
  # cryptsetup here is only for interactive use; the initrd LUKS stack pulls in
  # its own copy independently of this list.
  local.primaryUser.extraPackages = with pkgs; [
    cryptsetup
    libraspberrypi
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
