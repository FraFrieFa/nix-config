{ pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs; [
    ripgrep
    fd
    jq
    curl
    python3
    gcc
  ] ++ [
    pkgs-unstable.codex
  ];
}
