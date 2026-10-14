{ pkgs, lib, ... }:
# The built-in AX201 is screenpuck's e2e radio, not an uplink (eno1 is). It is
# out of NetworkManager's hands: a system wpa_supplicant owns it, and members of
# `screenpuck-dev` drive it through the control sockets in /run/sp-wifi with
# plain wpa_cli (no sudo). By default it runs the `screenpuck-test` AP; tests
# switch it to station (joining the Pi's hotspot) or Wi-Fi Direct (Miracast
# source, group owner) and back.
#
# Addressing follows wpa_supplicant's events through a root wpa_cli action
# script, so tests never need privileges:
#   AP up            -> 10.42.1.1/24, system dnsmasq leases, NAT out eno1
#   station joined   -> udhcpc lease, no default route, only the hotspot subnet
#                       and 192.0.2.1/32 (screenpuck's captive address) via the
#                       card; lease facts in /run/sp-wifi/lease
#   P2P group (GO)   -> 192.168.49.1/24, system dnsmasq leases the sink
# The AX201 cannot run AP and P2P GO at the same time: tests disable the AP
# network first.
#
# The PSK stays out of the store: /etc/nixos-secrets/screenpuck-ap.env
# (root:users 0640, so tests can read it) holds SCREENPUCK_AP_PSK=...
let
  dev = "wlp0s20f3";
  run = "/run/sp-wifi";
  captiveIp = "192.0.2.1";

  globalConf = ''
    ctrl_interface=DIR=${run} GROUP=screenpuck-dev
    update_config=0
    ap_scan=1
    device_name=e2e-source
    device_type=1-0050F204-1
    config_methods=keypad display
    p2p_go_intent=15
    p2p_listen_reg_class=81
    p2p_listen_channel=1
    p2p_oper_reg_class=81
    p2p_oper_channel=1
  '';

  mkConf = pkgs.writeShellScript "sp-wifi-conf" ''
    set -eu
    . /etc/nixos-secrets/screenpuck-ap.env
    umask 077
    mkdir -p ${run}
    cat > ${run}/wpa.conf <<EOF
    ${globalConf}
    network={
      ssid="screenpuck-test"
      mode=2
      frequency=2412
      key_mgmt=WPA-PSK
      proto=RSN
      pairwise=CCMP
      psk="$SCREENPUCK_AP_PSK"
    }
    EOF
    chgrp screenpuck-dev ${run}
    chmod 0750 ${run}
  '';

  # udhcpc -s: sets the address and the two routes, records the lease.
  dhcpScript = pkgs.writeShellScript "sp-wifi-udhcpc" ''
    PATH=${lib.makeBinPath [ pkgs.iproute2 pkgs.coreutils ]}
    case "$1" in
      bound|renew)
        ip addr flush dev "$interface"
        ip addr add "$ip/''${mask:-24}" dev "$interface"
        ip route replace ${captiveIp}/32 dev "$interface"
        printf 'ip=%s\nmask=%s\nrouter=%s\ndns=%s\n' "$ip" "$mask" "$router" "$dns" > ${run}/lease.tmp
        chmod 0644 ${run}/lease.tmp
        mv ${run}/lease.tmp ${run}/lease ;;
      deconfig)
        ip addr flush dev "$interface"
        rm -f ${run}/lease ;;
    esac
  '';

  # wpa_cli -a: $1 interface, $2 event, $3.. event fields
  action = pkgs.writeShellScript "sp-wifi-action" ''
    PATH=${lib.makeBinPath [ pkgs.iproute2 pkgs.coreutils pkgs.busybox pkgs.wpa_supplicant ]}
    case "$2" in
      AP-ENABLED|CONNECTED)
        [ "$1" = ${dev} ] || exit 0
        mode=$(wpa_cli -s ${run} -p ${run} -i ${dev} status | sed -n 's/^mode=//p')
        pkill -f "udhcpc -i ${dev}" || true
        rm -f ${run}/lease
        ip addr flush dev ${dev}
        case "$mode" in
          AP) ip addr add 10.42.1.1/24 dev ${dev} ;;
          station) udhcpc -i ${dev} -s ${dhcpScript} -b -t 10 -T 2 -O 114 ;;
        esac ;;
      DISCONNECTED|AP-DISABLED)
        [ "$1" = ${dev} ] || exit 0
        pkill -f "udhcpc -i ${dev}" || true
        rm -f ${run}/lease
        ip addr flush dev ${dev} ;;
      P2P-GROUP-STARTED)
        [ "$4" = GO ] || exit 0
        ip addr replace 192.168.49.1/24 dev "$3"
        ip link set "$3" up ;;
    esac
  '';

  watcher = iface: {
    description = "screenpuck test Wi-Fi addressing (${iface})";
    after = [ "sp-wifi.service" ];
    bindsTo = [ "sp-wifi.service" ];
    wantedBy = [ "sp-wifi.service" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.bash}/bin/sh -c 'for _ in $(seq 100); do [ -S ${run}/${iface} ] && exit 0; sleep 0.1; done; exit 1'";
      ExecStart = "${pkgs.wpa_supplicant}/bin/wpa_cli -s ${run} -p ${run} -i ${iface} -a ${action}";
      Restart = "always";
      RestartSec = 1;
    };
  };
in
{
  networking.networkmanager.unmanaged = [ dev ];

  systemd.services.sp-wifi = {
    description = "screenpuck test Wi-Fi (wpa_supplicant on ${dev})";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-${dev}.device" ];
    bindsTo = [ "sys-subsystem-net-devices-${dev}.device" ];
    serviceConfig = {
      ExecStartPre = mkConf;
      ExecStart = "${pkgs.wpa_supplicant}/bin/wpa_supplicant -i ${dev} -D nl80211 -c ${run}/wpa.conf";
      Restart = "on-failure";
    };
  };
  # The P2P device's socket name is cut to the 15-character interface limit.
  systemd.services.sp-wifi-sta = watcher dev;
  systemd.services.sp-wifi-p2p = watcher "p2p-dev-wlp0s20";
  # P2P group interfaces are cut the same way: p2p-wlp0s20-<n>.

  # Test AP and P2P group leases from the system dnsmasq (DHCP only, port=0).
  # AP clients get a router and a public resolver; the P2P sink gets neither.
  services.dnsmasq.settings = {
    interface = [ dev "p2p-wlp0s20-*" ];
    dhcp-range = [
      "set:testap,10.42.1.10,10.42.1.100,255.255.255.0,1h"
      "set:p2p,192.168.49.10,192.168.49.20,255.255.255.0,1h"
    ];
    dhcp-option = [
      "tag:testap,option:router,10.42.1.1"
      "tag:testap,option:dns-server,1.1.1.1"
    ];
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ dev ];
    externalInterface = "eno1";
  };

  # AP clients may reach only the DHCP server; the P2P sink also the e2e
  # Miracast source's WFD RTSP session (TCP 7236, served by test_miracast).
  networking.firewall.interfaces.${dev}.allowedUDPPorts = [ 67 ];
  networking.firewall.interfaces."p2p-wlp0s20-+" = {
    allowedUDPPorts = [ 67 ];
    allowedTCPPorts = [ 7236 ];
  };
}
