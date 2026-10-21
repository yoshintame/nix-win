set -eu
out=$1
fail() {
  echo "without-packages: $*" >&2
  exit 1
}
for f in winget.ps1 winget.json; do
  test ! -e "$out/$f" || fail "$f rendered without packages"
done
if grep -q winget "$out/nix-win.cmd" "$out/expected.tsv"; then fail "winget lines rendered without packages"; fi
