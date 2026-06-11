{ pkgs-unstable, ... }:
{
  users.users.fabius.packages = [
    pkgs-unstable.claude-code
    pkgs-unstable.teamspeak6-client
  ];
}
