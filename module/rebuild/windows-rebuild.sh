usage() {
  echo "usage: windows-rebuild switch|check [--flake <flake>#<host>] [--winget]" >&2
  exit 2
}

action=${1:-}
[ $# -gt 0 ] && shift
flake=$NIX_WIN_FLAKE
winget=()
while [ $# -gt 0 ]; do
  case $1 in
  --flake)
    flake=${2:?}
    shift 2
    ;;
  --winget)
    winget=(winget)
    shift
    ;;
  *) usage ;;
  esac
done
case $action in
switch) mode=apply ;;
check) mode=verify ;;
*) usage ;;
esac

start=$(date +%s%N)
sys32=/mnt/c/Windows/System32
windows() { "$@" </dev/null | tr -d '\r'; }

out=$(nix build --no-link --print-out-paths "${flake%%#*}#nixosConfigurations.\"${flake##*#}\".config.windows.build.toplevel")
cd /mnt/c
report=$(mktemp)
trap 'rm -f "$report"' EXIT

high=false
if windows "$sys32/whoami.exe" /groups | grep -E 'S-1-16-(12288|16384)' >/dev/null; then high=true; fi

run=("$sys32/cmd.exe")
if [ "$mode" = apply ] && ! $high; then
  if ! windows "$sys32/reg.exe" query 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' /v Enabled | grep -E 'REG_DWORD +0x[23]$' >/dev/null; then
    echo "nix-win: sudo.exe must run inline or with input disabled; run windows-rebuild switch once from an administrator terminal" >&2
    exit 1
  fi
  run=("$sys32/sudo.exe" 'C:\Windows\System32\cmd.exe')
  echo "nix-win: applying through sudo"
fi

if [ "$mode" = apply ] || $high; then
  entry="$(wslpath -w "$out")\\stage.cmd"
else
  copy=$(wslpath -u "$(windows "$sys32/cmd.exe" /d /c 'echo %TEMP%')")/nix-win
  rm -rf "$copy"
  cp -rL --no-preserve=mode "$out" "$copy"
  entry="$(wslpath -w "$copy")\\nix-win.cmd"
fi

failed=0
"${run[@]}" /d /c "$entry" "$mode" "${winget[@]}" </dev/null | tr -d '\r' >"$report" || failed=1
awk -F '\t' -f "$NIX_WIN_COMPARE" "$report" "$out/expected.tsv" || failed=1

echo "nix-win: $action took $((($(date +%s%N) - start) / 1000000)) ms"
exit "$failed"
