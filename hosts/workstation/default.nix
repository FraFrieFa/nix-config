{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/fabius-default.nix
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/programming.nix
    ../../profiles/claude.nix
    ../../profiles/unfree.nix
  ];

  networking.hostName = "workstation";

  # Build and install the aarch64 Raspberry Pi system from this x86_64 host.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  local.disk.full_disk = {
    id = "REPLACE-ME-workstation";
    overProvisioning = "100G";
  };

  local.primaryUser.extraPackages = with pkgs; [
    screen
    rpiboot
    picocom
    v4l-utils
  ];

  local.primaryUser.authorizedKeys = [
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDPgm7K7t41fVBh5Jajl4+vPyJO7jA45U8soik3sgL4kAAAACnNzaDpmYWJpdXM= fabius yubikey ssh"
  ];

  # Dedicated login for Nix remote builds from small LAN machines such as
  # miix310. Add the miix310-generated public key here after creating it.
  users.users.nixremote = {
    isNormalUser = true;
    description = "Nix remote build user";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhxIG58pNvYbq8Pydptcw2H9+9QfNkjFu2yP6311ekE root@miix310 nix builder"
    ];
  };

  nix.settings.trusted-users = [
    "@wheel"
    "nixremote"
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  system.stateVersion = "26.05";
}
