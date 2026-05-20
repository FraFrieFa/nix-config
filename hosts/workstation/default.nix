{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/programming.nix
    ../../profiles/signaged_dev.nix
    ../../profiles/unfree.nix
  ];

  networking.hostName = "workstation";

  users.users.fabius.packages = with pkgs; [
    screen
    rpiboot
    picocom
    v4l-utils
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
