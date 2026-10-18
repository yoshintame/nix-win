{
  lib,
  pkgs,
  cfg,
}:
let
  inherit (lib)
    concatLists
    concatMap
    concatMapStrings
    concatStringsSep
    imap1
    mapAttrsToList
    mergeAttrsList
    ;

  stateDir = "%ProgramFiles%\\nix-win";
  cmd = import ./cmd.nix { inherit lib; };
  registry = import ./registry.nix { inherit lib cmd; };
  commands = import ./commands.nix {
    inherit
      lib
      cmd
      cfg
      stateDir
      ;
  };

  numbered = imap1 (i: operation: operation // { index = cmd.pad i; });
  machine = numbered (
    registry {
      root = "HKLM";
      label = "HKLM";
    } cfg.registry.HKLM
  );
  hkcu = numbered (
    registry {
      root = "%root%";
      label = "HKCU";
    } cfg.registry.HKCU
  );
  users = builtins.attrNames cfg.users;

  verify =
    scope: operations:
    concatMap (operation: [
      "echo @@ ${scope} ${operation.index}"
      "${operation.query} 2>nul"
    ]) operations;

  expected =
    scope: prefix: operations:
    map (
      operation:
      concatStringsSep "\t" [
        scope
        operation.index
        operation.kind
        "${prefix}${operation.label}"
        operation.line
      ]
    ) operations;

  userSection =
    i: name:
    let
      label = "user_${toString i}";
      ntuser = "${cfg.users.${name}.profile}\\NTUSER.DAT";
      skip = reason: "(echo skip ${cmd.escapeEcho "${name}: ${reason}"}& exit /b 0)";
    in
    cmd.subroutine label [
      "set \"scope=user-${name}\""
      "set \"root=HKCU\""
      "if /i \"%USERNAME%\"==\"${name}\" goto ${label}_body"
      "if not defined admin ${skip "reading another user's HKCU needs an administrator session"}"
      "if not exist ${cmd.quote ntuser} ${skip "no profile at ${ntuser}"}"
      "set \"root=HKU\\nix-win-${name}\""
      "reg unload \"%root%\" >nul 2>&1"
      "reg load \"%root%\" ${cmd.quote ntuser} >nul 2>&1 || ${skip "hive in use"}"
      ":${label}_body"
      "if \"%mode%\"==\"apply\" call :hkcu_apply"
      "call :hkcu_verify"
      "if not \"%root%\"==\"HKCU\" call :unload"
    ];

  header = [
    "@echo off"
    "chcp 65001 >nul"
    "setlocal EnableExtensions DisableDelayedExpansion"
    "set \"PATH=%SystemRoot%\\System32;%SystemRoot%;%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\""
    "set \"PSModulePath=%ProgramFiles%\\WindowsPowerShell\\Modules;%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\Modules\""
  ];
  powershellFile = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File";

  powershellScript = concatStringsSep "\n" (
    [
      "$global:ErrorActionPreference = 'Stop'"
      "$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')"
      "$failed = $false"
      "function Invoke-Step([string]$Label, [scriptblock]$Body) { try { & $Body } catch { Write-Output \"FAILED \${Label}: $($_.Exception.Message -replace '\\s+', ' ')\"; $script:failed = $true } }"
    ]
    ++ map (step: "Invoke-Step ${cmd.psString step.label} {\n${step.body}\n}") commands.powershell
    ++ [
      "if ($failed) { exit 1 }"
      ""
    ]
  );

  stage = header ++ [
    "${powershellFile} \"%~dp0stage.ps1\" \"${stateDir}\" || (echo FAILED staging into ${stateDir}& exit /b 1)"
    "call \"${stateDir}\\current\\nix-win.cmd\" %1"
  ];

  script = concatLists [
    header
    [
      "set \"mode=%~1\""
      "set failed=0"
      "set \"admin=\""
      "whoami /groups | findstr /c:\"S-1-16-12288\" /c:\"S-1-16-16384\" >nul && set \"admin=1\""
      "if \"%mode%\"==\"apply\" if not defined admin (echo FAILED applying needs an administrator session& exit /b 1)"
      "if \"%mode%\"==\"apply\" call :apply"
      "call :verify_machine"
    ]
    (imap1 (i: _: "call :user_${toString i}") users)
    [ "exit /b %failed%" ]
    (cmd.subroutine "apply" (concatLists [
      (lib.optional (commands.powershell != [ ]) "${powershellFile} \"%~dp0nix-win.ps1\" || set failed=1")
      commands.services
      (map (file: "call :${file.label}") commands.files)
      (map (operation: operation.apply) machine)
      commands.power
      commands.tasks
    ]))
    (concatMap (file: cmd.subroutine file.label file.body) commands.files)
    (cmd.subroutine "verify_machine" ([ "echo @@ machine 0000" ] ++ verify "machine" machine))
    (concatLists (imap1 userSection users))
    (cmd.subroutine "hkcu_apply" (map (operation: operation.apply) hkcu))
    (cmd.subroutine "hkcu_verify" (verify "%scope%" hkcu))
    (cmd.subroutine "unload" [
      "for /l %%i in (1,1,3) do (reg unload \"%root%\" >nul 2>&1 && exit /b 0 & ping -n 2 127.0.0.1 >nul)"
      "echo FAILED unload %root%& set failed=1"
    ])
  ];

  bom = builtins.fromJSON ''"\ufeff"'';

  outputs = {
    "nix-win.cmd" = cmd.crlf script;
    "stage.cmd" = cmd.crlf stage;
    "stage.ps1" = bom + builtins.readFile ./stage.ps1;
    "expected.tsv" = concatMapStrings (row: row + "\n") (
      expected "machine" "" machine ++ concatMap (name: expected "user-${name}" "${name}: " hkcu) users
    );
  }
  // lib.optionalAttrs (commands.powershell != [ ]) { "nix-win.ps1" = bom + powershellScript; }
  // mergeAttrsList (map (file: file.output) commands.files);
in
pkgs.runCommand "nix-win" { } (
  lib.concatStrings (
    mapAttrsToList (
      path: text: "install -D -m 644 ${pkgs.writeText (baseNameOf path) text} $out/${path}\n"
    ) outputs
  )
)
