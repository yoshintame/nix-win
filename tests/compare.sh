set -eu
compare=$1
expected=$2
dir=$(mktemp -d)
rows=$(wc -l <"$expected")
test "$rows" -gt 0

awk -F '\t' '{ print "@@ " $1 " " $2; if ($3 == "value") print $5; else if ($3 == "present") print $4 }' "$expected" >"$dir/ok"
awk -F '\t' -f "$compare" "$dir/ok" "$expected" >"$dir/out"
grep -qx "nix-win: $rows ok, 0 drift, 0 missing" "$dir/out"

: >"$dir/empty"
if awk -F '\t' -f "$compare" "$dir/empty" "$expected" >"$dir/out"; then exit 1; fi
grep -qx 'nix-win: no results from Windows' "$dir/out"

sed '0,/REG_DWORD    0x1$/s//REG_DWORD    0x0/' "$dir/ok" >"$dir/drift"
if awk -F '\t' -f "$compare" "$dir/drift" "$expected" >"$dir/out"; then exit 1; fi
grep -q '^drift    ' "$dir/out"

awk '/^@@ / { keep = $2 != "machine" } keep' "$dir/ok" >"$dir/users"
if awk -F '\t' -f "$compare" "$dir/users" "$expected" >"$dir/out"; then exit 1; fi
grep -q ', machine not checked$' "$dir/out"
