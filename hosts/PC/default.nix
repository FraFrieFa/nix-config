{ pkgs, lib, ... }:
{
  imports = [
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
    ../../profiles/gaming.nix
  ];

  networking.hostName = "PC";

  hardware.graphics.enable = true;

  system.stateVersion = "26.05";
}
