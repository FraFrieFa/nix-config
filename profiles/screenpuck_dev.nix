{ config, lib, pkgs, ... }:
let
  cfg = config.local.screenpuck;
  # usb-<name> per configured port; each Pi gets .2 of its own /24.
  links = lib.mapAttrsToList (name: p: {
    iface = "usb-${name}";
    inherit (p) usbPort;
    net = "10.42.${toString p.subnet}";
  }) cfg.ports;
  ifaces = map (l: l.iface) links;
in
{
  options.local.screenpuck.ports = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        usbPort = lib.mkOption {
          type = lib.types.str;
          example = "1-1.3";
          description = "Kernel USB port path the Pi hangs off (udev KERNELS glob; \"*\" = any).";
        };
        subnet = lib.mkOption {
          type = lib.types.ints.between 0 255;
          description = "Third octet: this host is 10.42.<subnet>.1, the Pi 10.42.<subnet>.2.";
        };
      };
    });
    default.screenpuck = { usbPort = "*"; subnet = 0; };
    description = ''
      USB gadget links, one per attached Pi, named usb-<name>. The Pi carries
      no identity of its own (same image, fixed gadget MAC), so the port it is
      plugged into picks its address: this host's dnsmasq leases exactly
      10.42.<subnet>.2 on that link, with no router or DNS (no internet relay).
    '';
  };

  config = lib.mkMerge [
    {
      users.groups.screenpuck-dev = {};
      users.users.fabius.extraGroups = lib.mkAfter [ "dialout" "screenpuck-dev" ];

      users.users.fabius.packages = with pkgs; [
        ffmpeg
        cheese
      ];

      services.udev.extraRules = ''
        # Raspberry Pi BCM2708 boot modes, used by rpiboot.
        SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2763", GROUP:="screenpuck-dev", MODE:="0664"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2764", GROUP:="screenpuck-dev", MODE:="0664"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", ATTR{idProduct}=="2711", GROUP:="screenpuck-dev", MODE:="0664"
        # Name each Pi Zero W USB gadget link by the port it is plugged into
        ${lib.concatMapStrings (l: ''
          SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a[12]", KERNELS=="${l.usbPort}", NAME="${l.iface}"
        '') links}        # Pi SD card exposed as USB mass storage after rpiboot (msd) — allow flashing without root
        SUBSYSTEM=="block", ATTRS{idVendor}=="0a5c", ATTRS{idProduct}=="0001", GROUP="screenpuck-dev", MODE="0660"
      '';

      # The udev rule above grants raw read/write on the gadget's block device,
      # but mounting is a separate kernel privilege (CAP_SYS_ADMIN) that device
      # ownership cannot confer -- so `nix run .#flash` mounts p2 through
      # udisks2, and udisks2 asks polkit.
      #
      # udisks2's filesystem-mount default is <allow_active>yes</allow_active>,
      # which means active *and seated*. An SSH session is active but attached
      # to no seat, so flashing over SSH falls through to <allow_any>auth_admin
      # and fails with NotAuthorizedCanObtain -- while the same command run at
      # the physical Plasma session succeeds silently. This rule is what makes
      # a remote flash work unattended.
      #
      # Scoped to the gadget's own serial (the Pi enumerates as
      # "Linux File-Stor Gadget" with serial "rpizero"), so it grants nothing
      # for any other disk -- narrower than the VID/PID udev match above.
      # filesystem-mount, not -mount-system: the gadget reports HintSystem=false.
      #
      # eject-media is needed as well, not just mounting: the flash flow ends by
      # ejecting the mass-storage LUN, and that eject is what reboots the Pi back
      # into boot-ROM USB mode for the second rpiboot phase. It carries the same
      # seat-based default, so it fails over SSH for the same reason.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
               action.id == "org.freedesktop.udisks2.filesystem-unmount-others" ||
               action.id == "org.freedesktop.udisks2.eject-media") &&
              action.lookup("drive.serial") == "rpizero" &&
              subject.isInGroup("screenpuck-dev")) {
            return polkit.Result.YES;
          }
        });
      '';

      # Resolve the device's TLS hostname to its USB gadget IP so
      # https://local.screenpuck.com works from this host over the USB link (the Pi's
      # own dnsmasq only answers Wi-Fi AP clients, not the point-to-point USB link).
      networking.hosts."10.42.0.2" = [ "local.screenpuck.com" ];

      # One manual-address NM profile per link: this host is .1 of the link's /24.
      networking.networkmanager.ensureProfiles.profiles = lib.listToAttrs (map (l:
        lib.nameValuePair "screenpuck-${l.iface}" {
          connection = {
            id = "screenpuck-${l.iface}";
            type = "ethernet";
            "interface-name" = l.iface;
            autoconnect = true;
          };
          ipv4 = {
            method = "manual";
            address1 = "${l.net}.1/24";
          };
          ipv6.method = "ignore";
        }) links);

      # DHCP only (port=0: no DNS), one single-address pool per link, and an
      # empty router/DNS option: the Pi gets an address, never internet.
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          port = 0;
          bind-dynamic = true;
          interface = ifaces;
          dhcp-authoritative = true;
          dhcp-range = map (l: "${l.net}.2,${l.net}.2,255.255.255.0,12h") links;
          dhcp-option = [ "option:router" "option:dns-server" ];
        };
      };

      # Point-to-point USB gadget links to the Pis: trust them fully so DHCP,
      # ICMP and anything else reach the Pi without per-port firewall holes.
      networking.firewall.trustedInterfaces = ifaces;
    }
  ];
}
