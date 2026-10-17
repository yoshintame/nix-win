{
  lib,
  pkgs,
  cfg,
}:
let
  inherit (lib)
    concatLists
    concatMap
    concatStringsSep
    imap1
    mapAttrsToList
    ;

  cmd = import ./cmd.nix { inherit lib; };
  registry = import ./registry.nix { inherit lib cmd; };
  commands = import ./commands.nix { inherit lib cmd cfg; };

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
    [
      ":${label}"
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
      "exit /b 0"
    ];

  script = concatLists [
    [
      "@echo off"
      "chcp 65001 >nul"
      "setlocal DisableDelayedExpansion"
      "set \"PATH=%SystemRoot%\\System32;%SystemRoot%;%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\""
      "set \"mode=%~1\""
      "set failed=0"
      "set \"admin=\""
      "whoami /groups | findstr /c:\"S-1-16-12288\" /c:\"S-1-16-16384\" >nul && set \"admin=1\""
      "if \"%mode%\"==\"apply\" if not defined admin (echo FAILED applying needs an administrator session& exit /b 1)"
      "if \"%mode%\"==\"apply\" call :apply"
      "call :verify_machine"
    ]
    (imap1 (i: _: "call :user_${toString i}") users)
    [
      "exit /b %failed%"
      ":apply"
    ]
    commands.capabilities
    commands.firewall
    commands.services
    commands.files
    (map (operation: operation.apply) machine)
    commands.power
    commands.tasks
    commands.adapters
    [
      "exit /b 0"
      ":verify_machine"
    ]
    (verify "machine" machine)
    [ "exit /b 0" ]
    (concatLists (imap1 userSection users))
    [ ":hkcu_apply" ]
    (map (operation: operation.apply) hkcu)
    [
      "exit /b 0"
      ":hkcu_verify"
    ]
    (verify "%scope%" hkcu)
    [
      "exit /b 0"
      ":unload"
      "for /l %%i in (1,1,3) do (reg unload \"%root%\" >nul 2>&1 && exit /b 0 & ping -n 2 127.0.0.1 >nul)"
      "echo FAILED unload %root%& set failed=1& exit /b 0"
    ]
  ];

  outputs = {
    "nix-win.cmd" = cmd.crlf script;
    "expected.tsv" = lib.concatMapStrings (row: row + "\n") (
      expected "machine" "" machine ++ concatMap (name: expected "user-${name}" "${name}: " hkcu) users
    );
  }
  // commands.fileOutputs;
in
pkgs.runCommand "nix-win" { } (
  lib.concatStrings (
    mapAttrsToList (
      path: text: "install -D -m 644 ${pkgs.writeText (baseNameOf path) text} $out/${path}\n"
    ) outputs
  )
)
