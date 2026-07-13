{ pkgs, pkgs-unstable, ... }:
let
  pythonWithBrowserAutomation = pkgs.python3.withPackages (ps: with ps; [
    selenium
  ]);
  toml = pkgs.formats.toml {};
in
{
  environment.variables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  environment.etc."codex/managed_config.toml".source = toml.generate "codex-managed-config.toml" {
    mcp_servers.playwright = {
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [ "--user-data-dir" "/tmp/playwright-mcp-fabius" ];
    };
  };

  users.users.fabius.packages = with pkgs; [
    pythonWithBrowserAutomation
    gcc
    geckodriver
    nodejs_22
    playwright-driver
    playwright-mcp
    rust-analyzer
    file
  ] ++ [
    pkgs-unstable.codex
  ];
}
