{ lib, ... }:
{
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
  security.sudo.execWheelOnly      = true;

  users.users.root.hashedPassword = "!";

  security.pam.u2f = {
    enable       = true;
    settings.cue = true;
  };
  security.pam.services.login.u2fAuth = true;

  networking.firewall.enable    = true;
  networking.firewall.allowPing = false;
}
