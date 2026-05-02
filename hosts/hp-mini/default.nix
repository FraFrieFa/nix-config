{ config, pkgs, lib, ... }:
{
  imports = [
    ../../profiles/disk.nix
    ../../profiles/desktop.nix
  ];

  networking.hostName = "hp-mini";

  system.stateVersion = "26.05";
}
