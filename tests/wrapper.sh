set -eu
wrapper=$1
dir=$(mktemp -d)
fail() {
  echo "wrapper: $*" >&2
  exit 1
}

printf '#!%s\n' "$(command -v bash)" >"$dir/winget.exe"
cat >>"$dir/winget.exe" <<'FAKE'
echo "$*" >>"$FAKE_DIR/calls"
case $1 in
install)
  echo "Found $FAKE_NAME [$FAKE_ID] Version 1.0"
  if [ -n "${FAKE_ALREADY:-}" ]; then
    echo "Found an existing package already installed. Trying to upgrade the installed package..."
    echo "No available upgrade found."
    exit 43
  fi
  if [ -n "${FAKE_FAIL:-}" ]; then
    echo "Installer failed with exit code: 1603"
    exit 20
  fi
  echo "Successfully installed"
  ;;
uninstall)
  echo "Found $FAKE_NAME [$FAKE_ID]"
  if [ -n "${FAKE_FAIL:-}" ]; then
    echo "Uninstall failed with exit code: 1603"
    exit 20
  fi
  echo "Successfully uninstalled"
  ;;
list)
  echo "Name Id Version Source"
  echo "$FAKE_NAME $FAKE_ID 1.0 ${FAKE_SOURCE:-winget}"
  ;;
*) echo "passthrough $*" ;;
esac
FAKE
chmod +x "$dir/winget.exe"

export FAKE_DIR=$dir NIX_WIN_WINGET_EXE=$dir/winget.exe NIX_WIN_WINGET_BUNDLE=$dir/winget.bundle.json
run() { "$wrapper" "$@" >"$dir/out" 2>&1; }
bundle() { jq -cS . "$NIX_WIN_WINGET_BUNDLE"; }

FAKE_NAME=Steam FAKE_ID=Valve.Steam run install steam
test "$(bundle)" = '{"Valve.Steam":{}}' || fail "steam not recorded: $(bundle)"
grep -qx 'install steam --scope machine' "$dir/calls" || fail "install without --scope machine: $(cat "$dir/calls")"

FAKE_NAME="NVIDIA App" FAKE_ID=XP8CLZL93F5Z4P FAKE_SOURCE=msstore run install XP8CLZL93F5Z4P
test "$(jq -c '.XP8CLZL93F5Z4P' "$NIX_WIN_WINGET_BUNDLE")" = '{"name":"NVIDIA App","source":"msstore"}' || fail "msstore entry: $(bundle)"

FAKE_NAME=Spotify FAKE_ID=Spotify.Spotify run install Spotify.Spotify --scope user
jq -e 'has("Spotify.Spotify") | not' "$NIX_WIN_WINGET_BUNDLE" >/dev/null || fail "user-scope install recorded"
grep -q 'not recorded' "$dir/out" || fail "no note for a user-scope install"

FAKE_NAME=Tailscale FAKE_ID=Tailscale.Tailscale run install Tailscale.Tailscale
jq -e 'has("Tailscale.Tailscale") | not' "$NIX_WIN_WINGET_BUNDLE" >/dev/null || fail "module package recorded"
grep -q 'declared in a Nix module' "$dir/out" || fail "no note for a module package"

if FAKE_NAME=Broken FAKE_ID=Broken.App FAKE_FAIL=1 run install Broken.App; then fail "failed install exited 0"; fi
jq -e 'has("Broken.App") | not' "$NIX_WIN_WINGET_BUNDLE" >/dev/null || fail "failed install recorded"

FAKE_NAME="Beta App [Preview]" FAKE_ID=Beta.App run install Beta.App
test "$(jq -c 'keys' "$NIX_WIN_WINGET_BUNDLE")" = '["Beta.App","Valve.Steam","XP8CLZL93F5Z4P"]' || fail "id not taken from the last brackets: $(bundle)"

code=0
FAKE_NAME=Git FAKE_ID=Git.Git FAKE_ALREADY=1 run install Git.Git || code=$?
test "$code" = 43 || fail "winget's exit code not passed through: $code"
jq -e 'has("Git.Git")' "$NIX_WIN_WINGET_BUNDLE" >/dev/null || fail "an already installed package is not recorded"

if FAKE_NAME=Steam FAKE_ID=Valve.Steam FAKE_FAIL=1 run uninstall Valve.Steam; then fail "failed uninstall exited 0"; fi
jq -e 'has("Valve.Steam")' "$NIX_WIN_WINGET_BUNDLE" >/dev/null || fail "failed uninstall removed the package"

FAKE_NAME=Steam FAKE_ID=Valve.Steam run uninstall Valve.Steam
jq -e 'has("Valve.Steam") | not' "$NIX_WIN_WINGET_BUNDLE" >/dev/null || fail "steam not removed"

FAKE_NAME=Tailscale FAKE_ID=Tailscale.Tailscale run uninstall Tailscale.Tailscale
grep -q 'remove it there' "$dir/out" || fail "no note for removing a module package"

run search notepad
grep -qx 'passthrough search notepad' "$dir/out" || fail "search not passed through"
