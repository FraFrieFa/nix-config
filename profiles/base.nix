{ config, pkgs, lib, modulesPath, ... }:
let
  nixosConfig = config.local.nixosConfig;
  primaryUser = config.local.primaryUser;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./keyboard.nix
  ];

  # The single human account on this machine. Profiles and hosts extend it
  # through the extra* list options rather than naming the user directly, so
  # nothing outside profiles/fabius-default.nix hardcodes a username.
  options.local.primaryUser = {
    name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Login name of the machine's primary (and only) human user.";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "GECOS description for the primary user.";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Groups to add on top of the base set.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Packages installed into the primary user's profile. This is the only
        supported way to install packages; environment.systemPackages is
        deliberately left unused across this config.
      '';
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "SSH public keys accepted for the primary user.";
    };
  };

  options.local.nixosConfig = {
    unfreePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Package names allowed despite an unfree license.";
    };
  };

  config = {
    assertions = [
      {
        assertion = primaryUser.name != null;
        message = "local.primaryUser.name must be set by hosts importing profiles/base.nix.";
      }
    ];

    users.users.${primaryUser.name} = {
      isNormalUser = true;
      inherit (primaryUser) description;
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "audio"
        "nixos-config"
        "dialout"
      ] ++ primaryUser.extraGroups;
      packages = (with pkgs; [
        curl
        fd
        git
        htop
        jq
        pciutils
        ripgrep
        unzip
        usbutils
        vim
        wget
      ]) ++ primaryUser.extraPackages;
      openssh.authorizedKeys.keys = primaryUser.authorizedKeys;
    };

    # Members can edit /etc/nixos in place. This is root-equivalent because config
    # changes are applied by root during rebuilds; only trusted users belong here.
    users.groups.nixos-config = {};

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) nixosConfig.unfreePackages;

    programs.git = {
      enable = true;
      config.safe.directory = "/etc/nixos";
    };

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    console = {
      packages = [ pkgs.terminus_font ];
      font     = "ter-v24n";
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
        user = primaryUser.name;
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

        # NOTE: activation snippets are concatenated into one script, so a bare
        # `exit` here would abort activation for every snippet ordered after
        # this one -- including udevd. Keep the clone inside the else branch.
        if [ -e ${path} ]; then
          echo "info: ${path} exists; skipping config repo clone"
        else
          ${pkgs.coreutils}/bin/install \
            -d -o ${user} -g ${group} -m 2775 ${path}

          gitAsUser clone --quiet ${repo} ${path}

          ${pkgs.coreutils}/bin/chown -R ${user}:${group} ${path}

          ${pkgs.coreutils}/bin/chmod -R g+rwX ${path}
          ${pkgs.findutils}/bin/find ${path} -type d \
            -exec ${pkgs.coreutils}/bin/chmod g+s {} +
        fi
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

    # YubiKey / FIDO2. The udev rules are what make the token reachable as a
    # normal user; without them /dev/hidraw* stays root-only and ssh-keygen
    # -t ed25519-sk fails even with libfido2 present. Rules apply on device
    # add, so an already-inserted key must be replugged after a switch.
    local.primaryUser.extraPackages = with pkgs; [
      libfido2
      yubikey-manager
    ];

    services.udev.packages = [ pkgs.yubikey-personalization ];
    services.pcscd.enable = true;

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
