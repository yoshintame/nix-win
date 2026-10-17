{
  lib,
  pkgs,
  cfg,
}:
let
  inherit (lib) concatLists imap1 mapAttrsToList;

  cmd = import ./cmd.nix { inherit lib; };
  registry = import ./registry.nix { inherit lib cmd; };
  commands = import ./commands.nix { inherit lib cmd cfg; };

  machine = registry {
    root = "HKLM";
    label = "HKLM";
    scope = "machine";
  } cfg.registry.HKLM;

  hkcu = registry {
    root = "%root%";
    label = "HKCU";
    scope = "user";
  } cfg.registry.HKCU;

  users = builtins.attrNames cfg.users;

  header = [
    "@echo off"
    "chcp 65001 >nul"
  ];

  userSection =
    i: name:
    let
      label = "user_${toString i}";
      hive = "HKU\\nix-win-${name}";
      ntuser = "${cfg.users.${name}.profile}\\NTUSER.DAT";
      skip = reason: "(echo skip ${cmd.escapeEcho "${name}: ${reason}"}& exit /b 0)";
    in
    lib.throwIfNot (builtins.match "[A-Za-z0-9._-]+" name != null)
      "nix-win: user name '${name}' must be alphanumeric"
      [
        ":${label}"
        "set \"root=HKCU\""
        "if /i \"%USERNAME%\"==\"${name}\" goto ${label}_body"
        "if not defined admin ${skip "reading another user's HKCU needs an administrator session"}"
        "if not exist ${cmd.quote ntuser} ${skip "no profile at ${ntuser}"}"
        "set \"root=${hive}\""
        "reg unload \"%root%\" >nul 2>&1"
        "reg load \"%root%\" ${cmd.quote ntuser} >nul 2>&1 || ${skip "hive in use"}"
        ":${label}_body"
        "set \"dir=%out%\\user-${name}\""
        "if \"%mode%\"==\"apply\" call :hkcu_apply"
        "call :hkcu_verify"
        "if \"%root%\"==\"HKCU\" exit /b 0"
        "reg unload \"%root%\" >nul 2>&1 || ${cmd.fail "unload ${hive}"}"
        "exit /b 0"
      ];

  usersCmd =
    header
    ++ [
      "set \"mode=%~1\""
      "set \"admin=\""
      "whoami /groups | find \"S-1-16-12288\" >nul && set \"admin=1\""
    ]
    ++ imap1 (i: _: "call :user_${toString i}") users
    ++ [ "exit /b 0" ]
    ++ concatLists (imap1 userSection users)
    ++ [ ":hkcu_apply" ]
    ++ hkcu.apply
    ++ [
      "exit /b 0"
      ":hkcu_verify"
    ]
    ++ hkcu.verify
    ++ [ "exit /b 0" ];

  verifyCmd =
    header
    ++ [
      "setlocal"
      "if not \"%~1\"==\"\" set \"out=%~1\""
      "set \"dir=%out%\\machine\""
    ]
    ++ machine.verify
    ++ [
      "if /i \"%~2\"==\"machine\" exit /b 0"
      "call \"%~dp0users.cmd\" verify"
      "exit /b 0"
    ];

  applyCmd =
    header
    ++ [
      "setlocal"
      "set \"out=%~1\""
      "set failed=0"
    ]
    ++ commands.capabilities
    ++ commands.firewall
    ++ commands.services
    ++ commands.files
    ++ machine.apply
    ++ commands.power
    ++ commands.tasks
    ++ commands.adapters
    ++ [ "call \"%~dp0users.cmd\" apply" ]
    ++ commands.onChange
    ++ [
      "call \"%~dp0verify.cmd\" \"%out%\" machine"
      "exit /b %failed%"
    ];

  lines = lib.concatMapStrings (l: l + "\n");

  outputs = {
    "apply.cmd" = cmd.crlf applyCmd;
    "users.cmd" = cmd.crlf usersCmd;
    "verify.cmd" = cmd.crlf verifyCmd;
    "expected.tsv" = lines (machine.expected ++ hkcu.expected);
    "users" = lines users;
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
