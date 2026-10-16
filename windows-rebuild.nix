{ pkgs, flake }:
pkgs.writeShellApplication {
  name = "windows-rebuild";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
  ];
  text = ''
    usage() {
      echo "usage: windows-rebuild switch|check [--flake <flake>#<host>]" >&2
      exit 2
    }

    action=''${1:-}
    [ $# -gt 0 ] && shift
    flake=${pkgs.lib.escapeShellArg flake}
    while [ $# -gt 0 ]; do
      case $1 in
        --flake)
          flake=''${2:?}
          shift 2
          ;;
        *) usage ;;
      esac
    done
    case $action in
      switch | check) ;;
      *) usage ;;
    esac

    start=$(date +%s%N)
    sys32=/mnt/c/Windows/System32
    run() { "$sys32/cmd.exe" /c "$@" </dev/null | tr -d '\r'; }
    cd /mnt/c

    out=$(nix build --no-link --print-out-paths "''${flake%%#*}#nixosConfigurations.\"''${flake##*#}\".config.windows.build.toplevel")
    dir=$(wslpath -u "$(run 'echo %TEMP%')")/nix-windows
    rm -rf "$dir"
    cp -rL --no-preserve=mode "$out" "$dir"
    win=$(wslpath -w "$dir")

    user=$(run 'echo %USERNAME%')
    caller=""
    while IFS= read -r u; do
      if [ "''${u,,}" = "''${user,,}" ]; then caller=$u; fi
    done <"$dir/users"

    high=false
    if "$sys32/whoami.exe" /groups </dev/null | grep -q S-1-16-12288; then high=true; fi

    failed=0
    if [ "$action" = switch ]; then
      if $high; then
        echo "nix-windows: applying as administrator"
        run "$win\\apply.cmd" || failed=1
      else
        echo "nix-windows: applying through sudo"
        "$sys32/sudo.exe" 'C:\Windows\System32\cmd.exe' /c "$win\\apply.cmd" | tr -d '\r' || failed=1
      fi
      if [ -z "$caller" ]; then echo "skip HKCU: $user is not in windows.users"; fi
    fi

    run "$win\\verify-machine.cmd"
    if [ -n "$caller" ]; then run "$win\\verify-user-$caller.cmd"; fi
    if [ "$action" = check ]; then
      while IFS= read -r u; do
        [ "$u" = "$caller" ] && continue
        if $high; then
          run "$win\\hive-$u.cmd" verify
        else
          echo "skip $u: reading another user's HKCU needs an administrator session"
        fi
      done <"$dir/users"
    fi

    awk -F '\t' -v dir="$dir" -v caller="$caller" '
      function trim(s) { gsub(/^ +| +$/, "", s); return s }
      $1 ~ /^user-/ && $1 != "user-" caller { next }
      $1 == "hive-" caller { next }
      {
        file = dir "/out/" $1 "/" $2 ".txt"
        status = (getline line < file)
        if (status < 0) { skipped[$1] = 1; next }
        found = 0; present = 0; actual = ""
        while (status > 0) {
          sub(/\r$/, "", line)
          if (line == $5) found = 1
          if (line ~ /[^ ]/) present = 1
          if (line ~ /^    /) actual = line
          status = (getline line < file)
        }
        close(file)
        if ($3 == "value" && found) ok++
        else if ($3 == "value" && present) { drift++; print "drift    " $4 ": " trim(actual) ", expected " trim($5) }
        else if ($3 == "value") { missing++; print "missing  " $4 }
        else if (present) { drift++; print "present  " $4 }
        else ok++
      }
      END {
        printf "nix-windows: %d ok, %d drift, %d missing", ok, drift, missing
        for (s in skipped) printf ", %s not checked", s
        print ""
        exit (drift + missing > 0)
      }
    ' "$dir/expected.tsv" || failed=1

    echo "nix-windows: $action took $(( ($(date +%s%N) - start) / 1000000 )) ms"
    exit "$failed"
  '';
}
