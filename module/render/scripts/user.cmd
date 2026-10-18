:@label@
set "scope=user-@name@"
set "root=HKCU"
if /i "%USERNAME%"=="@name@" goto @label@_body
if not defined admin (echo skip @name@: reading another user's HKCU needs an administrator session& exit /b 0)
if not exist @ntuser@ (echo skip @name@: no profile at @ntuserEcho@& exit /b 0)
set "root=HKU\nix-win-@name@"
reg unload "%root%" >nul 2>&1
reg load "%root%" @ntuser@ >nul 2>&1 || (echo skip @name@: hive in use& exit /b 0)
:@label@_body
if "%mode%"=="apply" call :hkcu_apply
call :hkcu_verify
if not "%root%"=="HKCU" call :unload
exit /b 0
