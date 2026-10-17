usage() {
  echo "usage: windows-rebuild switch|check [--flake <flake>#<host>]" >&2
  exit 2
}

action=${1:-}
[ $# -gt 0 ] && shift
flake=$NIX_WIN_FLAKE
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

out=$(nix build --no-link --print-out-paths "${flake%%#*}#nixosConfigurations.\"${flake##*#}\".config.windows.build.toplevel")
cd /mnt/c
payload=$(wslpath -w "$out")
results=$(wslpath -u "$(run 'echo %TEMP%')")/nix-win
rm -rf "$results"
mkdir -p "$results"
resultsWin=$(wslpath -w "$results")

failed=0
if [ "$action" = switch ]; then
  if "$sys32/whoami.exe" /groups </dev/null | grep -q S-1-16-12288; then
    echo "nix-win: applying as administrator"
    run "$payload\\apply.cmd" "$resultsWin" || failed=1
  else
    echo "nix-win: applying through sudo"
    "$sys32/sudo.exe" 'C:\Windows\System32\cmd.exe' /c "$payload\\apply.cmd" "$resultsWin" | tr -d '\r' || failed=1
  fi
else
  run "$payload\\verify.cmd" "$resultsWin"
fi

awk -F '\t' -v dir="$results" -v users="$(tr '\n' ' ' <"$out/users")" -f "$NIX_WIN_COMPARE" "$out/expected.tsv" || failed=1

echo "nix-win: $action took $(( ($(date +%s%N) - start) / 1000000 )) ms"
exit "$failed"
