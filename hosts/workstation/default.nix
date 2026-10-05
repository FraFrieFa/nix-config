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
    ../../profiles/screenpuck_dev.nix
  ];

  networking.hostName = "workstation";

  # Build and install the aarch64 Raspberry Pi system from this x86_64 host.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Ethernet is the only uplink; the built-in Wi-Fi card is a test AP for the
  # Pis (station-mode join tests). The USB links relay no internet.
  # Pi 1 (UART, capture card; switch 01C4) and Pi 2 (switch 01C5) by hub port.
  local.screenpuck.ports = {
    sp1 = { usbPort = "1-1.3"; subnet = 0; };
    sp2 = { usbPort = "1-8.3"; subnet = 2; };
  };

  # AP on the built-in AX201. Channel 1 matches the Pi's own AP: its chip runs
  # AP+STA+P2P on a single channel. "shared" = NM's dnsmasq hands out DHCP/DNS
  # on 10.42.1.0/24 and masquerades out the default route (eno1).
  # The AX201 cannot run AP and P2P-client/GO at the same time.
  # The PSK stays out of the store: /etc/nixos-secrets/screenpuck-ap.env
  # (root:users 0640, so tests can join) holds SCREENPUCK_AP_PSK=...
  networking.networkmanager.ensureProfiles.environmentFiles = [
    "/etc/nixos-secrets/screenpuck-ap.env"
  ];
  networking.networkmanager.ensureProfiles.profiles.screenpuck-test-ap = {
    connection = {
      id = "screenpuck-test-ap";
      type = "wifi";
      "interface-name" = "wlp0s20f3";
      autoconnect = true;
    };
    wifi = {
      mode = "ap";
      ssid = "screenpuck-test";
      band = "bg";
      channel = 1;
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "$SCREENPUCK_AP_PSK";
    };
    ipv4 = {
      method = "shared";
      address1 = "10.42.1.1/24";
    };
    ipv6.method = "ignore";
  };
  # Only NM's dnsmasq (DHCP + DNS) is reachable from AP clients.
  networking.firewall.interfaces."wlp0s20f3" = {
    allowedUDPPorts = [ 53 67 ];
    allowedTCPPorts = [ 53 ];
  };

  local.disk.full_disk = {
    id = "REPLACE-ME-workstation";
    overProvisioning = "100G";
  };

  local.primaryUser.extraPackages = with pkgs; [
    screen
    rpiboot
    picocom
    v4l-utils
    iw
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
