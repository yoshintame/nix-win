{ config, lib, ... }:
let
  inherit (lib)
    concatLists
    mapAttrs
    mapAttrsToList
    mkIf
    mkMerge
    mkOption
    types
    ;

  key = root: path: values: {
    registry.${root} = lib.setAttrByPath (lib.splitString "\\" path) values;
  };

  helpers = {
    hklm = key "HKLM";
    hkcu = key "HKCU";
    on = v: if v then 1 else 0;
    off = v: if v then 0 else 1;
    service = name: v: {
      services.${name} = {
        startType = if v then "auto" else "disabled";
        state = if v then "running" else "stopped";
      };
    };
    tasks = names: v: {
      scheduledTasks = lib.genAttrs names (_: {
        enable = v;
      });
    };
  };

  tweak = {
    bool = description: apply: {
      type = types.bool;
      inherit description apply;
    };
    enum = values: description: apply: {
      type = types.enum (builtins.attrNames values);
      inherit description;
      apply = v: apply values.${v};
    };
  };

  groups =
    lib.genAttrs
      [
        "explorer"
        "start"
        "search"
        "suggestions"
        "privacy"
        "ai"
        "gaming"
        "system"
      ]
      (
        group:
        import ./${group}.nix {
          inherit tweak;
          inherit (helpers)
            hklm
            hkcu
            on
            off
            service
            tasks
            ;
        }
      );

  cfg = config.windows.defaults;
in
{
  options.windows.defaults = mapAttrs (
    _:
    mapAttrs (
      _: t:
      mkOption {
        type = types.nullOr t.type;
        default = null;
        inherit (t) description;
      }
    )
  ) groups;

  config.windows = mkMerge (
    concatLists (
      mapAttrsToList (
        group: tweaks:
        mapAttrsToList (
          name: t: mkIf (cfg.${group}.${name} != null) (mkMerge (t.apply cfg.${group}.${name}))
        ) tweaks
      ) groups
    )
  );
}
