{
  lib,
  pkgs,
  cfg,
}:
let
  inherit (lib) concatMap concatMapStrings;

  cmd = import ./cmd.nix { inherit lib; };
  registry = import ./registry.nix { inherit lib cmd cfg; };
  commands = import ./commands.nix { inherit lib cmd cfg; };

  inherit (registry) machine users;

  hiveFile =
    name:
    let
      hive = registry.hive name;
      key = cmd.quote "HKU\\lasthaze-${name}";
    in
    cmd.file "hive-${name}.cmd" (
      [
        "@echo off"
        "chcp 65001 >nul"
        "reg load ${key} ${cmd.quote "${cfg.users.${name}.profile}\\NTUSER.DAT"} >nul 2>&1"
        "if errorlevel 1 (echo skip ${cmd.escapeEcho name}: hive in use& exit /b 0)"
        "if /i not \"%~1\"==\"apply\" goto verify"
      ]
      ++ hive.imports
      ++ [ ":verify" ]
      ++ hive.queries
      ++ [ "reg unload ${key} >nul 2>&1 || ${cmd.fail "unload HKU\\lasthaze-${name}"}" ]
    );

  userCall =
    name:
    "if /i \"%USERNAME%\"==${cmd.quote name} (call \"%~dp0user-${name}.cmd\") else (call \"%~dp0hive-${name}.cmd\" apply)";

  apply = cmd.script "apply.cmd" (
    commands.capabilities
    ++ commands.files
    ++ machine.imports
    ++ commands.services
    ++ commands.firewall
    ++ commands.power
    ++ commands.tasks
    ++ commands.adapters
    ++ map userCall users
    ++ commands.onChange
  );

  perUser = name: [
    (cmd.file "user-${name}.cmd" ([ "@echo off" ] ++ (registry.user name).imports))
    (cmd.script "verify-user-${name}.cmd" (registry.user name).queries)
    (hiveFile name)
  ];

  scopes = [
    machine
  ]
  ++ concatMap (name: [
    (registry.user name)
    (registry.hive name)
  ]) users;

  lines = concatMapStrings (l: l + "\n");

  outputs = [
    apply
    (cmd.script "verify-machine.cmd" machine.queries)
    {
      path = "expected.tsv";
      encoding = "utf8";
      text = lines (concatMap (s: s.expected) scopes);
    }
    {
      path = "users";
      encoding = "utf8";
      text = lines users;
    }
  ]
  ++ concatMap (s: s.regFiles) scopes
  ++ concatMap perUser users
  ++ commands.fileOutputs;
in
pkgs.runCommand "nix-windows" {
  nativeBuildInputs = [
    pkgs.jq
    pkgs.iconv
  ];
  spec = builtins.toJSON (map (o: removeAttrs o [ "label" ]) outputs);
  passAsFile = [ "spec" ];
} (builtins.readFile ./write-files.sh)
