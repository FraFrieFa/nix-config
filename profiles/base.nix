{ config, pkgs, lib, modulesPath, ... }:
let
  # Source of the system configuration. On first activation /etc/nixos is
  # seeded from this specific commit, then becomes a mutable, group-writable
  # working copy that rebuilds read from directly. Bump configRev to roll the
  # pinned bootstrap version.
  configRepo = "https://github.com/FraFrieFa/nix-config";
  configRev  = "ef8ffe9f037a554395e15d8645a8ee26ed0c0e46";
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # /etc/nixos is owned root:nixos-config and group-writable so members of this
  # group can edit the config in place. Note this makes the group effectively
  # root-equivalent (rebuilds run activation as root) — only trusted users.
  users.groups.nixos-config = {};

  # /etc/nixos is root-owned but edited by group members, so git would refuse it
  # as "dubious ownership". Mark it safe system-wide.
  environment.etc."gitconfig".text = ''
    [safe]
        directory = /etc/nixos
  '';

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    packages = [ pkgs.terminus_font ];
    font     = "ter-v28b";
    keyMap = "de";
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    liberation_ttf
    dejavu_fonts
  ];

  fonts.fontconfig.enable = true;

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

  # Seed /etc/nixos with a pinned checkout of the config on first activation
  # (i.e. only when it does not already exist). Afterwards it is a normal git
  # working copy that members of the nixos-config group can edit in place.
  system.activationScripts.seedNixosConfig.text = ''
    if [ ! -e /etc/nixos/flake.nix ]; then
      export HOME=/root
      export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

      rm -rf /etc/nixos
      ${pkgs.git}/bin/git clone --quiet ${configRepo} /etc/nixos
      ${pkgs.git}/bin/git -C /etc/nixos checkout --quiet ${configRev}

      chown -R root:nixos-config /etc/nixos
      find /etc/nixos -type d -exec chmod 2775 {} +
      find /etc/nixos -type f -exec chmod g+w {} +
    fi
  '';

  security.sudo.wheelNeedsPassword = true;
  security.sudo.execWheelOnly      = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
  };

  boot.kernelPackages = pkgs.linuxPackages;

  zramSwap = {
    enable    = true;
    algorithm = "zstd";
  };

  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.kernelParams = [
    "oops=panic"
    "vsyscall=emulate"
    "debugfs=off"
    "page_alloc.shuffle=1"
    "randomize_kstack_offset=on"
    "8250.nr_uarts=0"
  ];

  boot.kernel.sysctl = {
    "kernel.kptr_restrict"             = 2;
    "kernel.dmesg_restrict"            = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.yama.ptrace_scope"         = 1;
    "kernel.core_pattern"              = "|/bin/false";
    "net.core.bpf_jit_harden"         = 2;
    "net.ipv4.conf.all.rp_filter"     = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "vm.mmap_rnd_bits"                 = 32;
    "vm.mmap_rnd_compat_bits"          = 16;
  };

  security.protectKernelImage      = true;
  security.forcePageTableIsolation = true;

  security.pam.u2f = {
    enable       = true;
    settings.cue = true;
  };
  security.pam.services = {
    login = {
      u2fAuth = true;
      unixAuth = true;
    };
    sddm = {
      u2fAuth = true;
      unixAuth = true;
    };
    sudo = {
      u2fAuth = true;
      unixAuth = true;
    };
  };

  networking.firewall.enable    = true;
  networking.firewall.allowPing = false;
}
