{
  description = "nix-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }:
  let
    system = "x86_64-linux";
    configRepo = "https://github.com/FraFrieFa/nix-config"; # set to "" to disable GitHub pull
    pkgs = import nixpkgs { inherit system; };
    pkgs-unstable = import nixpkgs-unstable { inherit system; };
  in {
    nixosConfigurations.PC = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs-unstable; };
      modules = [
        ./profiles/base.nix
        ./hosts/PC/default.nix
      ];
    };

    nixosConfigurations.hp-mini = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs-unstable; };
      modules = [
        ./profiles/base.nix
        ./hosts/hp-mini/default.nix
      ];
    };

    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { flakeSelf = self; inherit configRepo; };
      modules = [ ./installer ];
    };

    packages.${system} = {
      installer = self.nixosConfigurations.installer.config.system.build.isoImage;

      vm = let iso = self.packages.${system}.installer; in
        pkgs.writeShellApplication {
          name = "run-installer-vm";
          runtimeInputs = [ pkgs.qemu ];
          text = ''
            disk="''${INSTALLER_VM_DISK:-/tmp/nixos-installer-test.qcow2}"
            qmp="''${INSTALLER_VM_QMP:-/tmp/nixos-installer-test.qmp}"
            memory="''${INSTALLER_VM_MEMORY:-4096}"

            rm -f "$disk"
            qemu-img create -f qcow2 "$disk" 80G
            rm -f "$qmp"

            accel=()
            if [ -e /dev/kvm ]; then
              accel=(-enable-kvm)
            else
              accel=(-accel tcg)
            fi

            isofile=
            for f in "${iso}/iso/"*.iso; do isofile="$f"; done

            exec qemu-system-x86_64 \
              "''${accel[@]}" \
              -m "$memory" \
              -boot d \
              -cdrom "$isofile" \
              -drive "file=$disk,format=qcow2,if=virtio" \
              -netdev user,id=net0,hostfwd=tcp::2222-:22 \
              -device virtio-net-pci,netdev=net0 \
              -qmp "unix:$qmp,server,nowait" \
              -display curses
          '';
        };
    };

    apps.${system}.vm = {
      type = "app";
      program = "${self.packages.${system}.vm}/bin/run-installer-vm";
    };

    checks.${system}.installer-unit = pkgs.rustPlatform.buildRustPackage {
      pname = "nix-installer-unit";
      version = "0.1.0";
      src = ./installer;
      cargoLock.lockFile = ./installer/Cargo.lock;
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.openssl ];
    };

    devShells.${system}.installer = pkgs.mkShell {
      packages = with pkgs; [
        cargo
        rustc
        rustfmt
        clippy
        pkg-config
        openssl
        qemu
        socat
        tmux
        parted
        gptfdisk
        util-linux
        dosfstools
        e2fsprogs
        cryptsetup
      ];
    };
  };
}
