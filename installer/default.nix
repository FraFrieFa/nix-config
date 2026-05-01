{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    git
    nano
    parted
    cryptsetup
    dosfstools
    e2fsprogs
    jq
  ];

  programs.nano.nanorc = ''
    set autoindent
    set tabsize 2
    set tabstospaces
    set linenumbers
    set nohelp
    set nowrap
    set softwrap
  '';

  documentation.enable = false;
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

  console.keyMap = "de";

  system.stateVersion = "25.05";
}
