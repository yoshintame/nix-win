usage() {
  echo "usage: windows-rebuild switch|check [--flake <flake>#<host>]" >&2
  exit 2
}

action=${1:-}
[ $# -gt 0 ] && shift
flake=$NIX_WINDOWS_FLAKE
while [ $# -gt 0 ]; do
  case $1 in
    --flake)
      flake=${2:?}
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

out=$(nix build --no-link --print-out-paths "${flake%%#*}#nixosConfigurations.\"${flake##*#}\".config.windows.build.toplevel")
dir=$(wslpath -u "$(run 'echo %TEMP%')")/nix-windows
rm -rf "$dir"
cp -rL --no-preserve=mode "$out" "$dir"
win=$(wslpath -w "$dir")

user=$(run 'echo %USERNAME%')
caller=""
while IFS= read -r u; do
  if [ "${u,,}" = "${user,,}" ]; then caller=$u; fi
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

awk -F '\t' -v dir="$dir" -v caller="$caller" -f "$NIX_WINDOWS_COMPARE" "$dir/expected.tsv" || failed=1

echo "nix-windows: $action took $(( ($(date +%s%N) - start) / 1000000 )) ms"
exit "$failed"
