{ lib, buildLinux, fetchFromGitHub, ... }@args:

# Build the CachyOS kernel directly from their source.
# Update `rev` and `hash` when bumping the kernel version.
#
# To get a new hash:
#   nix-prefetch-github CachyOS linux-cachyos --rev <tag>

buildLinux (args // rec {
  version = "7.0.1";
  modDirVersion = version;

  src = fetchFromGitHub {
    owner = "CachyOS";
    repo  = "linux-cachyos";
    rev   = "v${version}-cachyos";
    hash  = lib.fakeHash; # replace after running: nix build .#linux-cachyos
  };

  # CachyOS ships its own .config in the repo root — use it directly.
  # Copy it out first:  cp <repo>/config-cachyos .config
  kernelConfigFile = ./config;

  # No extra patches needed: CachyOS patches are already in the source tree.
  kernelPatches = [];

  extraMeta = {
    description = "CachyOS Linux kernel — EEVDF + LTO + AutoFDO + Propeller + sched-ext";
    branch      = "cachyos";
  };
} // (args.argsOverride or {}))
