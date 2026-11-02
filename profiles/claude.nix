{ config, pkgs, pkgs-unstable, lib, ... }:
{
  local.nixosConfig.unfreePackages = [ "claude-code" ];

  local.primaryUser.extraPackages = [
    pkgs-unstable.claude-code
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
      command = "${pkgs.coreutils}/bin/env";
      args = [ "-u" "LD_LIBRARY_PATH" "${pkgs.playwright-mcp}/bin/playwright-mcp" "--user-data-dir" "/tmp/playwright-mcp-${config.local.primaryUser.name}" ];
    };
  };
}
