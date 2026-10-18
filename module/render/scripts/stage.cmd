@header@
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0stage.ps1" "@stateDir@" || (echo FAILED staging into @stateDir@& exit /b 1)
call "@stateDir@\current\nix-win.cmd" %1
