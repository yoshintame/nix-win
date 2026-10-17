set -eu
out=$1
script=$out/nix-win.cmd
if grep -qv $'\r$' "$script"; then
  echo "nix-win.cmd: line without CRLF" >&2
  exit 1
fi
grep -qF 'reg add "HKLM\SOFTWARE\NixWin\Example" /v "Quote" /t REG_SZ /d "say \"hi\" & 100%% done\\" /f' "$script"
grep -qF '/v "Monitor" /t REG_SZ /d "27\" monitor ^& ^(x86^)^" /f' "$script"
grep -qF 'reg query "HKLM\SOFTWARE\NixWin\Removed" >nul 2>&1 && (reg delete "HKLM\SOFTWARE\NixWin\Removed" /f' "$script"
grep -qF 'reg add "%root%\Software\NixWin\Empty" /f' "$script"
grep -qF 'reg load "%root%" "C:\Users\alice\NTUSER.DAT"' "$script"
grep -qF 'echo @@ %scope% ' "$script"
grep -qP '^machine\t\d{4}\tvalue\tHKLM\\SOFTWARE\\NixWin\\Example\\Cyrillic\t    Cyrillic    REG_SZ    Привет$' "$out/expected.tsv"
grep -qP '^machine\t\d{4}\tabsent\tHKLM\\SOFTWARE\\NixWin\\Example\\Gone\t$' "$out/expected.tsv"
grep -qP '^user-alice\t\d{4}\tpresent\talice: HKCU\\Software\\NixWin\\Empty\t$' "$out/expected.tsv"
test "$(cat "$out/files/0001")" = "key = value"
