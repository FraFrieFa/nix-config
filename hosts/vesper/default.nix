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
    uboot.enable = true;

    # DISABLED -- this override made the board unbootable. It replaces the
    # second-stage bootloader on the FAT partition with a rebuild of
    # rpi_arm64_defconfig plus the fragment below; the resulting u-boot.bin does
    # not come up on a Pi 5, so nothing downstream ever executes. Stock U-Boot
    # boots fine and only fails at `usb start` ("no USB controller found"), so
    # the cost of leaving this off is USB in U-Boot, not the system.
    #
    # The reasoning was sound as far as it went: Pi 5 USB hangs off the RP1
    # southbridge behind PCIe and is described in the DTB as bare
    # `compatible = "snps,dwc3"`, and xhci-dwc3 is the only in-tree driver
    # matching that (dwc3-generic matches vendor glue compatibles only, none of
    # which the Pi 5 uses). CONFIG_USB_XHCI_DWC3 alone evidently isn't enough to
    # produce a working image -- re-enabling this needs a build verified on the
    # board (serial console / recoverable SD) before it goes anywhere near /boot.
    #
    # uboot = {
    #   enable = true;
    #   package = pkgs.ubootRaspberryPiAarch64.override {
    #     extraConfig = ''
    #       CONFIG_USB_XHCI_DWC3=y
    #     '';
    #   };
    # };
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
    # The stock Pi 5 DTB already ships a complete fan curve: a `pwm-fan` node
    # (`cooling_fan`) plus a `cpu-thermal` zone whose four active trips map onto
    # fan states 1-4 (50/60/67.5/75 °C -> PWM 75/125/175/250 of 255, 5 °C
    # hysteresis, critical shutdown at 110 °C). The kernel thermal subsystem
    # drives it with no daemon; the node just ships `status = "disabled"` and the
    # firmware flips it to "okay" when it sees this dtparam.
    #
    # Nulling `dtparam` wholesale above (to drop nixos-hardware's `audio=on`
    # alongside the `dtoverlay` wipe that forces legacy firmware HDMI output)
    # silently took `cooling_fan` with it, leaving the fan dead and no cooling
    # device in /sys/class/thermal. mkForce stays so the default list is still
    # overridden outright rather than merged. `fan_temp0..3`, `_hyst` and
    # `_speed` overrides can retune the curve here if it turns out too loud.
    dtparam = lib.mkForce [ "cooling_fan=on" ];
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
  #
  # lm_sensors is purely for reading back CPU temperature and fan RPM; the fan
  # control loop itself lives in the kernel (see the cooling_fan dtparam above).
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
