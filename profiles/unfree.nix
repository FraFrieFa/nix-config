{ pkgs-unstable, lib, ... }:
{
  users.users.fabius.packages = [
    pkgs-unstable.claude-code
    pkgs-unstable.teamspeak6-client
  ];

  environment.etc."claude-code/managed-settings.json".text = lib.generators.toJSON {} {
    model = "opus";
    theme = "dark";
    effortLevel = "low";
    alwaysThinkingEnabled = false;
    attribution = {
      commit = "";
      pr = "";
    };
  };
}
