{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    packages = [ pkgs.terminus_font ];
    font     = "ter-v28b";
    keyMap = "de";
  };

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

  users.groups.nixos-config = {};

  users.users.fabius = {
    isNormalUser = true;
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" "nixos-config" ];
    shell        = pkgs.bash;
  };

  security.sudo.wheelNeedsPassword = true;
  security.sudo.execWheelOnly      = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
  };
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 30d";
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

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
  ];

  boot.kernel.sysctl = {
    "kernel.kptr_restrict"             = 2;
    "kernel.dmesg_restrict"            = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.yama.ptrace_scope"         = 2;
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
  security.pam.services.login.u2fAuth = true;

  networking.firewall.enable    = true;
  networking.firewall.allowPing = false;
}
