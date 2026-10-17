set -eu
out=$1
for f in apply.cmd users.cmd verify.cmd; do
  test -f "$out/$f"
  if grep -qv $'\r$' "$out/$f"; then echo "$f: line without CRLF" >&2; exit 1; fi
done
grep -qF 'reg add "HKLM\SOFTWARE\NixWin\Example" /v "Quote" /t REG_SZ /d "say \"hi\" & 100%% done\\" /f' "$out/apply.cmd"
grep -qF 'reg query "HKLM\SOFTWARE\NixWin\Removed" >nul 2>&1 && (reg delete "HKLM\SOFTWARE\NixWin\Removed" /f' "$out/apply.cmd"
grep -qF 'reg add "%root%\Software\NixWin\Empty" /f' "$out/users.cmd"
grep -qF 'reg load "%root%" "C:\Users\alice\NTUSER.DAT"' "$out/users.cmd"
grep -qP '^machine\t\d{4}\tvalue\tHKLM\\SOFTWARE\\NixWin\\Example\\Cyrillic\t    Cyrillic    REG_SZ    Привет$' "$out/expected.tsv"
grep -qP '^machine\t\d{4}\tabsent\tHKLM\\SOFTWARE\\NixWin\\Example\\Gone\t$' "$out/expected.tsv"
grep -qx alice "$out/users"
test "$(cat "$out/files/0001")" = "key = value"
