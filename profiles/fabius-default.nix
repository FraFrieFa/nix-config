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

  # Suppress zsh-newuser-install while keeping the system-wide zsh config.
  # Type "f" creates this empty file if absent without truncating an existing one.
  systemd.tmpfiles.rules = [
    "f /home/fabius/.zshrc 0644 fabius users - -"
  ];

  users.users.root.hashedPassword = "!";
}
