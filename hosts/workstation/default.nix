{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/fabius-default.nix
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/programming.nix
    ../../profiles/unfree.nix
  ];

  networking.hostName = "workstation";

  services.screenpuck-host.enable = true;

  local.disk.full_disk = {
    id = "REPLACE-ME-workstation";
    overProvisioning = "100G";
  };

  users.users.fabius.packages = with pkgs; [
    screen
    rpiboot
    picocom
    v4l-utils
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
      PermitRootLogin = "no";
    };
  };

  system.stateVersion = "26.05";
}
