{
  description = "nix-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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

  outputs = { nixpkgs, nixpkgs-unstable, disko, nixos-hardware, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    pkgs-unstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
        "claude-code"
        "teamspeak6-client"
      ];
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
        pkgs-unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
      modules = [
        disko.nixosModules.disko
        ./hosts/miix310/default.nix
      ];
    };

    nixosConfigurations.vesper = nixpkgs-unstable.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        disko.nixosModules.disko
        nixos-hardware.nixosModules.raspberry-pi-5
        ./hosts/vesper/default.nix
      ];
    };

  };
}
