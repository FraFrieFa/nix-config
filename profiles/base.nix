{ config, flakeSelf, pkgs, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

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

  systemd.tmpfiles.rules = [
    "d /etc/nixos 0755 root root -"
  ];

  environment.etc."nixos/flake.nix".source = "${flakeSelf}/flake.nix";

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
