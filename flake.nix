{
  description = "nix-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }:
  let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
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
      specialArgs = { flakeSelf = self; };
      modules = [ ./installer ];
    };

    packages.${system}.installer =
      self.nixosConfigurations.installer.config.system.build.isoImage;
  };
}
