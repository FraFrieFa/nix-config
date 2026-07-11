{ lib, pkgs, ... }:
{
  users.users.fabius.extraGroups = lib.mkAfter [ "dialout" ];

  users.users.fabius.packages = with pkgs; [
    ffmpeg
    cheese
  ];

  services.udev.extraRules = ''                                                                                                                                                                                                                                                                                             
    # Raspberry Pi BCM2708 boot modes, used by rpiboot.                                                                                                                                                                                                                                                                     
    SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2763", GROUP:="users", MODE:="0664"                                                                                                                                                                                                                         
    SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2764", GROUP:="users", MODE:="0664"                                                                                                                                                                                                                         
    # Rename Pi Zero W USB gadget ethernet to a stable name regardless of port
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a1", NAME="usb-screenpuck"
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a2", NAME="usb-screenpuck"
    # Pi SD card exposed as USB mass storage after rpiboot (msd) — allow flashing without root
    SUBSYSTEM=="block", ATTRS{idVendor}=="0a5c", ATTRS{idProduct}=="0001", GROUP="users", MODE="0660"
  '';                                                                                                                                                                                                                                                                                                                       
                                                                                                                                                                                                                                                                                                                            
  # Resolve the device's TLS hostname to its USB gadget IP so
  # https://local.screenpuck.com works from this host over the USB link (the Pi's
  # own dnsmasq only answers Wi-Fi AP clients, not the point-to-point USB link).
  networking.hosts."10.42.0.2" = [ "local.screenpuck.com" ];

  networking.networkmanager.ensureProfiles.profiles.screenpuck-pi-gadget = {
    connection = {
      id = "screenpuck-pi-gadget";
      type = "ethernet";
      "interface-name" = "usb-screenpuck";
      autoconnect = true;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.1/24";
    };
    ipv6.method = "ignore";
  };

  # The Pi boots its root over NFS from the userspace unfsd server (nix run .#up),
  # which serves NFS + MOUNT on TCP/UDP 2049 (started with -p, so no portmapper).
  # Open those ports only on the Pi gadget link so the kernel NFS-root mount can
  # reach the host; without this the inbound SYN to :2049 is silently dropped.
  networking.firewall.interfaces."usb-screenpuck" = {
    allowedTCPPorts = [ 2049 ];
    allowedUDPPorts = [ 2049 ];
  };

  # Point-to-point USB gadget link to the Pi: trust it fully so SSH (22),
  # ICMP and anything else reach the Pi without per-port firewall holes.
  networking.firewall.trustedInterfaces = [ "usb-screenpuck" ];

  # Relay internet to the Pi over the USB gadget link: masquerade traffic from
  # the 10.42.0.0/24 gadget subnet out through the host uplink. Enables IP
  # forwarding and installs the NAT/forward rules. The Pi reaches this via its
  # default route through 10.42.0.1 (set Pi-side).
  networking.nat = {
    enable = true;
    internalInterfaces = [ "usb-screenpuck" ];
    externalInterface = "enp0s31f6";
  };
}
