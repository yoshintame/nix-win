{
  lib,
  pkgs,
  cfg,
}:
let
  inherit (lib)
    attrNames
    attrValues
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

  fill =
    file: vars:
    let
      inline = lib.filterAttrs (_: builtins.isString) vars;
      fillLine =
        text:
        let
          block = builtins.match "@([A-Za-z]+)@" text;
          names = map builtins.head (builtins.filter builtins.isList (builtins.split "@([A-Za-z]+)@" text));
          unknown = builtins.filter (name: !(inline ? ${name})) names;
        in
        if block != null then
          vars.${builtins.head block}
          or (throw "nix-win: no lines for @${builtins.head block}@ in ${baseNameOf file}")
        else
          lib.throwIf (unknown != [ ])
            "nix-win: no value for @${builtins.head unknown}@ in ${baseNameOf file}"
            [
              (lib.replaceStrings (map (name: "@${name}@") (attrNames inline)) (attrValues inline) text)
            ];
    in
    concatMap fillLine (lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile file)));

  header = fill ./scripts/header.cmd { };

  userSection =
    i: name:
    let
      ntuser = "${cfg.users.${name}.profile}\\NTUSER.DAT";
    in
    fill ./scripts/user.cmd {
      inherit name;
      label = "user_${toString i}";
      ntuser = cmd.quote ntuser;
      ntuserEcho = cmd.escapeEcho ntuser;
    };

  powershellScript =
    builtins.readFile ./scripts/prelude.ps1
    + concatMapStrings (
      step: "Invoke-Step ${cmd.psString step.label} {\n${step.body}\n}\n"
    ) commands.powershell
    + "if ($failed) { exit 1 }\n";

  stage = fill ./scripts/stage.cmd { inherit header stateDir; };

  script = fill ./scripts/nix-win.cmd {
    inherit header;
    callUsers = imap1 (i: _: "call :user_${toString i}") users;
    apply = concatLists [
      (lib.optional (commands.powershell != [ ])
        "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%~dp0nix-win.ps1\" || set failed=1"
      )
      commands.services
      (map (file: "call :${file.label}") commands.files)
      (map (operation: operation.apply) machine)
      commands.power
      commands.tasks
    ];
    files = concatMap (file: cmd.subroutine file.label file.body) commands.files;
    verifyMachine = verify "machine" machine;
    users = concatLists (imap1 userSection users);
    hkcuApply = map (operation: operation.apply) hkcu;
    hkcuVerify = verify "%scope%" hkcu;
  };

  bom = builtins.fromJSON ''"\ufeff"'';

  outputs = {
    "nix-win.cmd" = cmd.crlf script;
    "stage.cmd" = cmd.crlf stage;
    "stage.ps1" = bom + builtins.readFile ./scripts/stage.ps1;
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
