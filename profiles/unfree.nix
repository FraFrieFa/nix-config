{ pkgs-unstable, ... }:
{
  environment.systemPackages = [
    pkgs-unstable.claude-code
    pkgs-unstable.teamspeak6-client
  ];
}
