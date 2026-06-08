{ pkgs, pkgs-unstable, ... }:
let
  pythonWithBrowserAutomation = pkgs.python3.withPackages (ps: with ps; [
    selenium
  ]);
in
{
  environment.variables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  environment.systemPackages = with pkgs; [
    ripgrep
    fd
    jq
    curl
    pythonWithBrowserAutomation
    gcc
    geckodriver
    nodejs_22
    playwright-driver
    playwright-mcp
    rust-analyzer
  ] ++ [
    pkgs-unstable.codex
  ];
}
