{ pkgs, ... }:
{
  users.groups.nixos-config = {};

  users.users.fabius = {
    isNormalUser = true;
    description = "Fabius";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "nixos-config"
      "dialout"
    ];
    shell = pkgs.bash;
    packages = with pkgs; [
      curl
      fd
      git
      htop
      jq
      pciutils
      ripgrep
      unzip
      usbutils
      vim
      wget
    ];
  };

  users.users.root.hashedPassword = "!";
}
