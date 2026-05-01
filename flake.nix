{
  description = "nix-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.PC = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./base.nix
        ./hosts/PC/default.nix
        ./hosts/PC/hardware.nix
      ];
    };

    nixosConfigurations.hp-mini = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./base.nix
        ./hosts/hp-mini/default.nix
        ./hosts/hp-mini/hardware.nix
      ];
    };

    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ ./installer ];
    };

    packages.${system}.installer =
      self.nixosConfigurations.installer.config.system.build.isoImage;
  };
}
