{ config, pkgs, lib, ... }:
{
  imports = [ ./hardening.nix ];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    font   = "Lat2-Terminus16";
    keyMap = "de";
  };

  services.xserver.xkb.layout = "de";

  programs.nano = {
    enable = true;
    nanorc = ''
      set tabsize 4
      set autoindent
      set linenumbers
      set positionlog
      set historylog
      include "${pkgs.nano}/share/nano/*.nanorc"
    '';
  };

  networking.networkmanager.enable = true;

  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
  };

  users.users.fabius = {
    isNormalUser = true;
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
    shell        = pkgs.bash;
  };
  security.sudo.wheelNeedsPassword = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
  };
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 30d";
  };
}
