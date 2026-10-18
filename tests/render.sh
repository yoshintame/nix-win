set -eu
out=$1
script=$out/nix-win.cmd
fail() {
  echo "render: $*" >&2
  exit 1
}
has() { grep -qF -- "$2" "$1" || fail "$1 lacks: $2"; }
hasE() { grep -qE -- "$2" "$1" || fail "$1 lacks /$2/"; }
hasP() { grep -qP -- "$2" "$1" || fail "$1 lacks /$2/"; }
for f in nix-win.cmd stage.cmd; do
  if grep -qv $'\r$' "$out/$f"; then fail "$f: line without CRLF"; fi
done
for f in nix-win.ps1 stage.ps1; do
  test "$(head -c 3 "$out/$f" | od -An -tx1 | tr -d ' ')" = efbbbf || fail "$f: no UTF-8 BOM"
done
has "$script" '%~dp0nix-win.ps1" || set failed=1'
has "$out/stage.cmd" '"%~dp0stage.ps1" "%ProgramFiles%\nix-win" || (echo FAILED staging into %ProgramFiles%\nix-win& exit /b 1)'
has "$out/stage.cmd" 'call "%ProgramFiles%\nix-win\current\nix-win.cmd" %1'
has "$out/nix-win.ps1" '$global:ErrorActionPreference = '"'Stop'"
has "$script" 'set "PSModulePath=%ProgramFiles%\WindowsPowerShell\Modules;%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"'
has "$script" 'echo @@ machine 0000'
for label in $(grep -o 'call :[A-Za-z0-9_]*' "$script" | cut -c7- | sort -u); do
  grep -q "^:$label"$'\r'"\$" "$script" || fail "nix-win.cmd calls :$label without the label"
done
has "$out/nix-win.ps1" "Invoke-Step 'firewall Example-In-TCP' {"
has "$out/nix-win.ps1" 'Set-NetFirewallRule -Name $n -NewDisplayName $d @p'
has "$out/nix-win.ps1" "LocalPort = '8080'"
has "$out/nix-win.ps1" "InterfaceAlias = 'Any'"
has "$script" 'findstr /b /c:key "%~dp0files\0001" >nul || (echo FAILED validate C:\ProgramData\NixWin\example.conf& set failed=1& exit /b 0)'
has "$script" 'echo changed || (echo FAILED on change of C:\ProgramData\NixWin\example.conf& set failed=1& exit /b 0)'
hasE "$script" '^if not exist "%ProgramFiles%\\nix-win\\pending\\[0-9a-f]{16}" exit /b 0'
hasE "$script" '^setlocal EnableExtensions DisableDelayedExpansion'
has "$script" 'reg add "HKLM\SOFTWARE\NixWin\Example" /v "Quote" /t REG_SZ /d "say \"hi\" & 100%% done\\" /f'
has "$script" '/v "Monitor" /t REG_SZ /d "27\" monitor ^& ^(x86^)^" /f'
has "$script" 'reg query "HKLM\SOFTWARE\NixWin\Removed" >nul 2>&1 && (reg delete "HKLM\SOFTWARE\NixWin\Removed" /f'
has "$script" 'reg add "%root%\Software\NixWin\Empty" /f'
has "$script" 'reg load "%root%" "C:\Users\alice\NTUSER.DAT"'
has "$script" 'echo @@ %scope% '
hasP "$out/expected.tsv" '^machine\t\d{4}\tvalue\tHKLM\\SOFTWARE\\NixWin\\Example\\Cyrillic\t    Cyrillic    REG_SZ    Привет$'
hasP "$out/expected.tsv" '^machine\t\d{4}\tabsent\tHKLM\\SOFTWARE\\NixWin\\Example\\Gone\t$'
hasP "$out/expected.tsv" '^user-alice\t\d{4}\tpresent\talice: HKCU\\Software\\NixWin\\Empty\t$'
test "$(cat "$out/files/0001")" = "key = value" || fail "files/0001 content"
