set -eu
wrapper=$1
dir=$(mktemp -d)
fail() {
  echo "wrapper: $*" >&2
  exit 1
}

printf '#!%s\n' "$(command -v bash)" >"$dir/winget.exe"
cat >>"$dir/winget.exe" <<'FAKE'
set -eu
all=$*
echo "$all" >>"$FAKE_DIR/calls"
state=$FAKE_DIR/installed
touch "$state"
command=$1
shift
id= scope= source=winget
while [ $# -gt 0 ]; do
  case $1 in
  --id | -q | --query) id=$2; shift ;;
  --scope) scope=$2; shift ;;
  -s | --source) source=$2; shift ;;
  --installer-type) shift ;;
  -*) ;;
  *) id=$1 ;;
  esac
  shift
done
canonical=${FAKE_CANONICAL:-$id}
find() { grep -i "^$1|" "$state" || true; }
case $command in
install)
  [ -z "${FAKE_FAIL:-}" ] || exit 20
  if [ -n "$(find "$canonical")" ]; then exit 43; fi
  echo "$canonical|${FAKE_SCOPE:-${scope:-user}}|${FAKE_SOURCE:-$source}|${FAKE_NAME:-$canonical}" >>"$state"
  ;;
uninstall)
  [ -z "${FAKE_FAIL:-}" ] || exit 20
  [ -n "$(find "$id")" ] || exit 20
  grep -vi "^$id|" "$state" >"$state.next" || true
  mv "$state.next" "$state"
  ;;
list)
  entry=$(find "$id")
  [ -n "$entry" ] || exit 20
  IFS='|' read -r eid escope esource ename <<<"$entry"
  if [ -n "$scope" ] && [ "$scope" != "$escope" ]; then exit 20; fi
  echo "Name Id Version Source"
  echo "------------------------"
  echo "$ename $eid 1.0 $esource"
  ;;
*) echo "passthrough $all" ;;
esac
FAKE
chmod +x "$dir/winget.exe"

export FAKE_DIR=$dir NIX_WIN_WINGET_EXE=$dir/winget.exe NIX_WIN_WINGET_BUNDLE=$dir/winget.bundle.json
run() { "$wrapper" "$@" >"$dir/out" 2>&1; }
keys() { jq -c 'keys' "$NIX_WIN_WINGET_BUNDLE"; }
entry() { jq -c --arg id "$1" '.[$id]' "$NIX_WIN_WINGET_BUNDLE"; }
says() { grep -q -- "$1" "$dir/out" || fail "no note '$1': $(cat "$dir/out")"; }

run install --id Valve.Steam
test "$(entry Valve.Steam)" = '{}' || fail "an exact winget install is not recorded: $(cat "$NIX_WIN_WINGET_BUNDLE")"
grep -qx 'install --id Valve.Steam --scope machine' "$dir/calls" || fail "install without --scope machine: $(cat "$dir/calls")"

FAKE_SOURCE=msstore FAKE_NAME="NVIDIA App" run install XP8CLZL93F5Z4P
test "$(entry XP8CLZL93F5Z4P)" = '{"name":"NVIDIA App","source":"msstore"}' || fail "msstore entry: $(entry XP8CLZL93F5Z4P)"

run install Spotify.Spotify --scope User
test "$(entry Spotify.Spotify)" = null || fail "a user-scope install is recorded"
says 'machine-wide packages only'

run install --id Tailscale.Tailscale
test "$(entry Tailscale.Tailscale)" = null || fail "a module package is recorded"
says 'declared in a Nix module'

if FAKE_FAIL=1 run install --id Broken.App; then fail "a failed install exits 0"; fi
test "$(entry Broken.App)" = null || fail "a failed install is recorded"

FAKE_CANONICAL=Valve.SteamBeta run install steam
test "$(entry steam)" = null || fail "a fuzzy query is recorded under the query"
test "$(entry Valve.SteamBeta)" = null || fail "a fuzzy query is recorded"
says 'pass the package ID with --id'

echo 'Git.Git|user|winget|Git' >>"$dir/installed"
code=0
run install --id Git.Git || code=$?
test "$code" = 43 || fail "winget's exit code is not passed through: $code"
test "$(entry Git.Git)" = null || fail "a package installed per-user is recorded as machine-wide"

code=0
run install --id valve.steam || code=$?
test "$code" = 43 || fail "winget's exit code is not passed through after recording: $code"
test "$(keys)" = '["Valve.Steam","XP8CLZL93F5Z4P"]' || fail "a differently cased id adds a key: $(keys)"

run install --id A.One --id B.Two
test "$(keys)" = '["Valve.Steam","XP8CLZL93F5Z4P"]' || fail "a multi-package install changes the bundle: $(keys)"
says 'one package per command'

run install --manifest ./x.yaml
says 'from a manifest'

run install --id Contoso.Tool --source contoso
test "$(entry Contoso.Tool)" = null || fail "a package from another source is recorded"

FAKE_SOURCE=contoso run install --id Private.Tool
test "$(entry Private.Tool)" = null || fail "a package listed from another source is recorded"
says 'comes from source contoso'

if FAKE_FAIL=1 run uninstall --id Valve.Steam; then fail "a failed uninstall exits 0"; fi
test "$(entry Valve.Steam)" = '{}' || fail "a failed uninstall removes the entry"

run uninstall --id VALVE.STEAM
test "$(entry Valve.Steam)" = null || fail "uninstall in another case keeps the entry"

run install --id Valve.Steam
test "$(entry Valve.Steam)" = '{}' || fail "reinstalling a package removed from the bundle is not recorded"

echo 'Tailscale.Tailscale|machine|winget|Tailscale' >>"$dir/installed"
run uninstall --id Tailscale.Tailscale
says 'remove it there'

run install --id AgileBits.1Password --installer-type MSI
test "$(entry AgileBits.1Password)" = '{"installerType":"msi"}' || fail "the installer type is not recorded: $(entry AgileBits.1Password)"

run install --id Other.Tool --installer-type=bogus
test "$(entry Other.Tool)" = null || fail "an unknown installer type is recorded"
says 'installer type bogus'

run install --id Spaced.Type --installer-type 'msi msix'
test "$(entry Spaced.Type)" = null || fail "an installer type with a space is recorded"

printf '[]' >"$NIX_WIN_WINGET_BUNDLE"
: >"$dir/calls"
if run install --id Other.App; then fail "an array bundle is accepted"; fi
test ! -s "$dir/calls" || fail "winget ran with an invalid bundle"

: >"$NIX_WIN_WINGET_BUNDLE"
run install --id Other.App
test "$(keys)" = '["Other.App"]' || fail "an empty bundle file is not treated as {}: $(keys)"

ln -s "$NIX_WIN_WINGET_BUNDLE" "$dir/link.json"
NIX_WIN_WINGET_BUNDLE=$dir/link.json run install --id Linked.App
test -L "$dir/link.json" || fail "writing the bundle replaced a symlink"
test "$(entry Linked.App)" = '{}' || fail "an install through a symlinked bundle is not recorded"

(
  flock 9
  sleep 3
) 9<>"$NIX_WIN_WINGET_BUNDLE" &
sleep 1
if timeout 1 "$wrapper" install --id Locked.App >"$dir/out" 2>&1; then fail "the bundle is written while another process holds its lock"; fi
wait

run search notepad
grep -qx 'passthrough search notepad' "$dir/out" || fail "search is not passed through"
