{ lib, pkgs, ... }:
{
  imports = [
    ../../profiles/disk.nix
  ];

  networking.hostName = "vesper";
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;
    networks."10-ethernet" = {
      matchConfig.Name = "end0 eth0";
      networkConfig.DHCP = "yes";
    };
  };
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

  boot.initrd.systemd.tpm2.enable = lib.mkForce false;
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
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  users.users.fabius = {
    isNormalUser = true;
    description = "Fabius";
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };
  users.users.root.initialPassword = "nixos";

  security.sudo.wheelNeedsPassword = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  system.stateVersion = "26.05";
}
