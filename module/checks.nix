{ lib, cfg }:
let
  inherit (lib)
    attrNames
    concatLists
    concatStringsSep
    filter
    hasPrefix
    mapAttrsToList
    optionals
    toLower
    ;
  patterns = import ./patterns.nix;

  each =
    what: regex: names:
    map (name: {
      assertion = builtins.match regex name != null;
      message = "nix-win: ${what} '${name}' must match ${builtins.toJSON regex}";
    }) names;

  unique =
    what: key: names:
    mapAttrsToList (_: group: {
      assertion = builtins.length group == 1;
      message = "nix-win: ${what}: ${concatStringsSep ", " group}";
    }) (builtins.groupBy (name: toLower (key name)) names);

  registry =
    root: keys:
    each "${root} key path" patterns.keyPath (attrNames keys)
    ++ unique "${root} key paths differ only in case" lib.id (attrNames keys)
    ++ concatLists (
      mapAttrsToList (
        path: values:
        if values == null then
          let
            writes = values: values == { } || lib.any (v: v != null) (lib.attrValues values);
            inside = filter (
              other:
              keys.${other} != null && writes keys.${other} && hasPrefix "${toLower path}\\" (toLower other)
            ) (attrNames keys);
          in
          [
            {
              assertion = inside == [ ];
              message = "nix-win: ${root}\\${path} is deleted, but keys under it are set: ${concatStringsSep ", " inside}";
            }
          ]
        else
          each "value name in ${root}\\${path}" patterns.plain (attrNames values)
          ++ unique "value names in ${root}\\${path} differ only in case" lib.id (attrNames values)
      ) keys
    );

  userClasses = map (path: {
    assertion = !(hasPrefix "software\\classes\\" "${toLower path}\\");
    message = "nix-win: HKCU\\${path} lives in UsrClass.dat, which a loaded NTUSER.DAT does not contain";
  }) (attrNames cfg.registry.HKCU);

  rules = attrNames cfg.firewall.rules;
  firewall =
    each "firewall rule name" patterns.name rules
    ++ unique "firewall rule names differ only in case" lib.id rules
    ++ unique "firewall rules share a display name" (name: cfg.firewall.rules.${name}.displayName) rules
    ++ concatLists (
      mapAttrsToList (
        name: rule:
        optionals (rule.localPort != null) [
          {
            assertion = builtins.elem rule.protocol [
              "TCP"
              "UDP"
            ];
            message = "nix-win: firewall rule ${name} sets localPort, which needs protocol TCP or UDP";
          }
        ]
      ) cfg.firewall.rules
    );
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
++ each "user name" patterns.name (attrNames cfg.users)
++ unique "user names differ only in case" lib.id (attrNames cfg.users)
++ firewall
++ each "service name" patterns.name (attrNames cfg.services)
++ unique "service names differ only in case" lib.id (attrNames cfg.services)
++ each "power setting" patterns.powerSetting (attrNames cfg.power.timeouts)
++ each "network adapter property" patterns.word (attrNames cfg.networkAdapters.powerManagement)
++ each "scheduled task" patterns.plain (attrNames cfg.scheduledTasks)
++ unique "scheduled tasks differ only in case" lib.id (attrNames cfg.scheduledTasks)
++ each "file path" patterns.plain (attrNames cfg.files)
++ unique "file paths differ only in case" lib.id (attrNames cfg.files)
