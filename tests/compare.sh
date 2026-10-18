set -eu
compare=$1
expected=$2
dir=$(mktemp -d)
rows=$(wc -l <"$expected")
fail() {
  echo "compare: $*" >&2
  exit 1
}
test "$rows" -gt 0 || fail "empty expected.tsv"

report() {
  awk -F '\t' -v mode="$1" '
    { print "@@ " $1 " " $2 }
    $3 == "value" && !(mode == "missing" && !dropped++) { print $5 }
    $3 == "present" { print $4 }
    $3 == "absent" && mode == "present" && !added++ { print "    Leftover    REG_SZ    x" }
  ' "$expected"
}
run() { awk -F '\t' -f "$compare" "$dir/$1" "$expected" >"$dir/$1.out"; }
pass() {
  run "$1" || fail "$1: exit $?: $(cat "$dir/$1.out")"
  grep -qx -- "$2" "$dir/$1.out" || fail "$1 lacks: $2"
}
reject() {
  if run "$1"; then fail "$1: passed: $(cat "$dir/$1.out")"; fi
  grep -q -- "$2" "$dir/$1.out" || fail "$1 lacks: $2"
}

report ok >"$dir/ok"
pass ok "nix-win: $rows ok, 0 drift, 0 missing"

: >"$dir/empty"
reject empty '^nix-win: no results from Windows$'

sed '0,/REG_DWORD    0x1$/s//REG_DWORD    0x0/' "$dir/ok" >"$dir/drift"
reject drift '^drift    '

report missing >"$dir/missing"
reject missing '^missing  '

report present >"$dir/present"
reject present '^present  '

awk '/^@@ / { keep = $2 != "machine" } keep' "$dir/ok" >"$dir/users"
reject users ', machine not checked$'
