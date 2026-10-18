@header@
set "mode=%~1"
set failed=0
set "admin="
whoami /groups | findstr /c:"S-1-16-12288" /c:"S-1-16-16384" >nul && set "admin=1"
if "%mode%"=="apply" if not defined admin (echo FAILED applying needs an administrator session& exit /b 1)
if "%mode%"=="apply" call :apply
call :verify_machine
@callUsers@
exit /b %failed%
:apply
@apply@
exit /b 0
@files@
:verify_machine
echo @@ machine 0000
@verifyMachine@
exit /b 0
@users@
:hkcu_apply
@hkcuApply@
exit /b 0
:hkcu_verify
@hkcuVerify@
exit /b 0
:unload
for /l %%i in (1,1,3) do (reg unload "%root%" >nul 2>&1 && exit /b 0 & ping -n 2 127.0.0.1 >nul)
echo FAILED unload %root%& set failed=1
exit /b 0
