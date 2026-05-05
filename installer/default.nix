{ config, pkgs, lib, modulesPath, flakeSelf, configRepo ? "", ... }:
let
  nix-installer = pkgs.rustPlatform.buildRustPackage {
    pname = "nix-installer";
    version = "0.1.0";
    src = ./.;
    cargoLock.lockFile = ./Cargo.lock;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.openssl ];
    meta.mainProgram = "nix-installer";
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../profiles/base.nix
  ];

  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" ];

  boot.kernelParams = [ "nomodeset" "vga=normal" ];

  boot.loader.grub.gfxmodeBios = "text";

  environment.systemPackages = with pkgs; [
    git
    parted
    cryptsetup
    dosfstools
    e2fsprogs
    jq
    nix-installer
  ];

  environment.etc."nix-config".source = flakeSelf;
  environment.etc."nix-config-url".text = "${configRepo}\n";

  documentation.enable       = false;
  documentation.nixos.enable = false;

  users.users.root.initialHashedPassword = lib.mkForce null;

  services.getty.autologinUser = lib.mkForce "root";

  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ] && [ -z "$INSTALLER_RAN" ]; then
      export INSTALLER_RAN=1
      nix-installer
    fi
  '';

  system.stateVersion = "26.05";
}
