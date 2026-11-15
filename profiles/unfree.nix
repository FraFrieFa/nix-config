{ pkgs, ... }:
{
  local.nixosConfig = {
    unfreePackages = [
      "nvidia-x11"
      "nvidia-kernel-modules"
      "nvidia-settings"
      "steam"
      "steam-unwrapped"
      "teamspeak6-client"
    ];
  };

  local.primaryUser.extraPackages = [
    (pkgs.callPackage ../pkgs/teamspeak6-wrapped { })
  ];
}
