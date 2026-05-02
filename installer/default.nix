{ config, pkgs, lib, modulesPath, flakeSelf, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../profiles/base.nix
  ];

  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" ];

  environment.systemPackages = with pkgs; [
    git
    parted
    cryptsetup
    dosfstools
    e2fsprogs
    jq
  ];

  environment.etc."nix-config".source = flakeSelf;

  documentation.enable       = false;
  documentation.nixos.enable = false;

  environment.etc."install.sh" = {
    mode = "0755";
    text = builtins.readFile ./install.sh;
  };

  services.getty.autologinUser = lib.mkForce "root";

  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ] && [ -z "$INSTALLER_RAN" ]; then
      export INSTALLER_RAN=1
      /etc/install.sh
    fi
  '';

  system.stateVersion = "26.05";
}
