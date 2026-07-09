{ pkgs, pkgs-unstable, lib, ... }:
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
    permissions.defaultMode = "plan";
    attribution = {
      commit = "";
      pr = "";
    };
  };

  environment.etc."claude-code/managed-mcp.json".text = lib.generators.toJSON {} {
    mcpServers.playwright = {
      type = "stdio";
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [ "--user-data-dir" "/tmp/playwright-mcp-fabius" ];
    };
  };
}
