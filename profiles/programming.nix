{ config, lib, pkgs, pkgs-unstable, ... }:
let
  pythonWithBrowserAutomation = pkgs.python3.withPackages (ps: with ps; [
    selenium
  ]);
  toml = pkgs.formats.toml {};
  playwrightUserDataDir = "/tmp/playwright-mcp-${config.local.primaryUser.name}";
  playwrightHeadless = lib.optional config.local.playwright.headless "--headless";
in
{
  # Headless unless a host wants the visible browser (only the desktop does).
  options.local.playwright.headless = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };

  config = {
    environment.variables = {
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };

    environment.etc."codex/managed_config.toml".source = toml.generate "codex-managed-config.toml" {
      mcp_servers.playwright = {
        command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
        args = [ "--user-data-dir" playwrightUserDataDir ] ++ playwrightHeadless;
      };
    };

    local.primaryUser.extraPackages = with pkgs; [
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
  };
}
