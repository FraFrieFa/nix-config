{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./keyboard.nix
  ];

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

  # Ensure /etc/nixos is a writable checkout of the config repository.
  system.activationScripts.seedNixosConfig = {
    deps = [ "users" ];

    text = let
      user = "fabius";
      group = "nixos-config";
      path = "/etc/nixos";
      httpsRepo = "https://github.com/FraFrieFa/nix-config";
      sshRepo = "git@github.com:FraFrieFa/nix-config.git";
    in ''
      gitAsUser() {
        ${pkgs.util-linux}/bin/runuser -u ${user} -- \
          ${pkgs.coreutils}/bin/env \
            GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
            ${pkgs.git}/bin/git "$@"
      }

      valid=false

      metadata="$(${pkgs.coreutils}/bin/stat -c '%U:%G:%a' ${path} 2>/dev/null || true)"
      if { [ "$metadata" = "${user}:${group}:2755" ] ||
           [ "$metadata" = "${user}:${group}:2775" ]; } &&
         origin="$(gitAsUser -C ${path} remote get-url origin 2>/dev/null)"; then
        case "$origin" in
          ${httpsRepo}|${httpsRepo}.git|${sshRepo}) valid=true ;;
        esac
      fi


      if [ "$valid" != true ]; then
        ${pkgs.coreutils}/bin/rm -rf ${path}

        ${pkgs.coreutils}/bin/install \
          -d -o ${user} -g ${group} -m 2775 ${path}

        gitAsUser clone --quiet ${httpsRepo} ${path}
      fi

      gitAsUser -C ${path} remote set-url origin ${sshRepo}

      ${pkgs.coreutils}/bin/chown -R ${user}:${group} ${path}

      ${pkgs.findutils}/bin/find ${path} -type d \
        -exec ${pkgs.coreutils}/bin/chmod 2775 {} +

      ${pkgs.findutils}/bin/find ${path} -type f \
        -exec ${pkgs.coreutils}/bin/chmod g+rw {} +
    '';
  };

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
