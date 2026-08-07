{ config, pkgs, lib, modulesPath, ... }:
let
  nixosConfig = config.local.nixosConfig;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./keyboard.nix
  ];

  options.local.nixosConfig = {
    owner = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User that owns and clones the /etc/nixos config checkout.";
    };

  };

  config = {
    assertions = [
      {
        assertion = nixosConfig.owner != null;
        message = "local.nixosConfig.owner must be set by hosts importing profiles/base.nix.";
      }
    ];

    # Members can edit /etc/nixos in place. This is root-equivalent because config
    # changes are applied by root during rebuilds; only trusted users belong here.
    users.groups.nixos-config = {};

    programs.git = {
      enable = true;
      config.safe.directory = "/etc/nixos";
    };

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

    # Seed /etc/nixos once. Existing checkouts are left completely untouched.
    system.activationScripts.seedNixosConfig = {
      deps = [ "users" ];

      text = let
        user = nixosConfig.owner;
        group = "nixos-config";
        path = "/etc/nixos";
        repo = "https://github.com/FraFrieFa/nix-config";
      in ''
        gitAsUser() {
          ${pkgs.util-linux}/bin/runuser -u ${user} -- \
            ${pkgs.coreutils}/bin/env \
              GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              ${pkgs.git}/bin/git "$@"
        }

        if [ -e ${path} ]; then
          echo "info: ${path} exists; skipping config repo clone"
          exit 0
        fi

        ${pkgs.coreutils}/bin/install \
          -d -o ${user} -g ${group} -m 2775 ${path}

        gitAsUser clone --quiet ${repo} ${path}

        ${pkgs.coreutils}/bin/chown -R ${user}:${group} ${path}

        ${pkgs.coreutils}/bin/chmod -R g+rwX ${path}
        ${pkgs.findutils}/bin/find ${path} -type d \
          -exec ${pkgs.coreutils}/bin/chmod g+s {} +
      '';
    };

    security.sudo.wheelNeedsPassword = true;
    security.sudo.execWheelOnly      = true;

    services.openssh.settings.PermitRootLogin = "no";

    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;
    };

    zramSwap = {
      enable    = true;
      algorithm = "zstd";
    };

    hardware.cpu.intel.updateMicrocode = lib.mkIf pkgs.stdenv.hostPlatform.isx86 (
      lib.mkDefault config.hardware.enableRedistributableFirmware
    );

    boot.kernelParams = [
      "oops=panic"
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
      "vm.mmap_rnd_bits"                 = if pkgs.stdenv.hostPlatform.isAarch64 then 24 else 32;
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
  };
}
