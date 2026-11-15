{ symlinkJoin, writeShellScript, teamspeak6-client }:

let
  launcher = writeShellScript "TeamSpeak" ''
    cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/TeamSpeak/Default"
    log="''${XDG_CACHE_HOME:-$HOME/.cache}/TeamSpeak/launcher.log"
    mkdir -p "$(dirname "$log")"
    {
      echo "=== $(date -Is) launch pid=$$ args=$*"
      if [ -e "$cfg/next.patch" ]; then
        echo "removing stale self-update patch $(stat -c '%s bytes, %y' "$cfg/next.patch")"
        rm -f "$cfg/next.patch"
      fi
      pgrep -a -f '/teamspeak6-client/TeamSpeak$' | sed 's/^/already running: /'
    } >>"$log" 2>&1
    start=$(date +%s%N)
    ${teamspeak6-client}/bin/TeamSpeak "$@" 2> >(tail -n 40 >"$log.stderr.tmp")
    rc=$?
    wait
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
    {
      echo "=== $(date -Is) exit pid=$$ rc=$rc after ''${ms}ms"
      if [ "$ms" -lt 5000 ]; then
        echo "--- early exit, last stderr:"
        cat "$log.stderr.tmp"
      fi
    } >>"$log" 2>&1
    rm -f "$log.stderr.tmp"
    exit $rc
  '';
in
symlinkJoin {
  name = "teamspeak6-client-wrapped";
  paths = [ teamspeak6-client ];
  postBuild = ''
    rm $out/bin/TeamSpeak
    cp ${launcher} $out/bin/TeamSpeak
  '';
}
