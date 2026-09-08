{
  description = "nix-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Keep the Miix kernel on the nixpkgs revision of its currently running
    # system. Its hand-crafted kernel is expensive enough that routine updates
    # must not silently change the kernel derivation and trigger a local rebuild.
    miix-nixpkgs.url = "github:NixOS/nixpkgs/21ea275a7c46aef9d4d6ddc962e6d562e9d94183";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { nixpkgs, miix-nixpkgs, nixpkgs-unstable, disko, nixos-hardware, ... }:
  let
    system = "x86_64-linux";
    pkgs-unstable-for = system: import nixpkgs-unstable {
      inherit system;
      config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
        "claude-code"
      ];
    };
    pkgs-unstable = pkgs-unstable-for system;
    miix-kernel-pkgs = import miix-nixpkgs {
      inherit system;
    };
  in {
    nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs-unstable; };
      modules = [
        disko.nixosModules.disko
        ./hosts/desktop/default.nix
      ];
    };

    nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs-unstable; };
      modules = [
        disko.nixosModules.disko
        ./hosts/workstation/default.nix
      ];
    };

    nixosConfigurations.miix310 = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit pkgs-unstable;
        miixKernelPkgs = miix-kernel-pkgs;
      };
      modules = [
        disko.nixosModules.disko
        ./hosts/miix310/default.nix
      ];
    };

    nixosConfigurations.vesper = nixpkgs-unstable.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        pkgs-unstable = pkgs-unstable-for "aarch64-linux";
      };
      modules = [
        disko.nixosModules.disko
        nixos-hardware.nixosModules.raspberry-pi-5
        ./hosts/vesper/default.nix
      ];
    };

    nixosConfigurations.solace = nixpkgs-unstable.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        pkgs-unstable = pkgs-unstable-for "aarch64-linux";
      };
      modules = [
        disko.nixosModules.disko
        nixos-hardware.nixosModules.raspberry-pi-4
        ./hosts/solace/default.nix
      ];
    };

  };
}
