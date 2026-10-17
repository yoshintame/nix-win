{ lib, cfg }:
let
  inherit (lib)
    attrNames
    concatLists
    concatStringsSep
    mapAttrsToList
    optionals
    toLower
    ;

  matches = regex: name: builtins.match regex name != null;

  each =
    what: regex: names:
    map (name: {
      assertion = matches regex name;
      message = "nix-win: ${what} '${name}' must match ${regex}";
    }) names;

  plain = what: each what "[^\r\n\t\"]+";

  caseUnique =
    what: names:
    mapAttrsToList (_: group: {
      assertion = builtins.length group == 1;
      message = "nix-win: ${what} differ only in case: ${concatStringsSep ", " group}";
    }) (builtins.groupBy toLower names);

  registry =
    root: keys:
    plain "${root} key path" (attrNames keys)
    ++ caseUnique "${root} key paths" (attrNames keys)
    ++ concatLists (
      mapAttrsToList (
        path: values:
        optionals (values != null) (
          plain "value name in ${root}\\${path}" (attrNames values)
          ++ caseUnique "value names in ${root}\\${path}" (attrNames values)
        )
      ) keys
    );

  userClasses = map (path: {
    assertion = !(lib.hasPrefix "software\\classes\\" "${toLower path}\\");
    message = "nix-win: HKCU\\${path} lives in UsrClass.dat, which a loaded NTUSER.DAT does not contain";
  }) (attrNames cfg.registry.HKCU);
in
registry "HKLM" cfg.registry.HKLM
++ registry "HKCU" cfg.registry.HKCU
++ userClasses
++ [
  {
    assertion = cfg.registry.HKCU == { } || cfg.users != { };
    message = "nix-win: windows.registry.HKCU is set but windows.users is empty, so nothing applies it";
  }
]
++ each "user name" "[A-Za-z0-9._-]+" (attrNames cfg.users)
++ each "firewall rule name" "[A-Za-z0-9._-]+" (attrNames cfg.firewall.rules)
++ each "service name" "[A-Za-z0-9._-]+" (attrNames cfg.services)
++ each "power setting" "[a-z-]+" (attrNames cfg.power.timeouts)
++ each "network adapter property" "[A-Za-z]+" (attrNames cfg.networkAdapters.powerManagement)
++ plain "scheduled task" (attrNames cfg.scheduledTasks)
++ plain "file path" (attrNames cfg.files)
