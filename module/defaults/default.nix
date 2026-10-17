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

  key = root: path: values: { registry.${root}.${path} = values; };

  helpers = {
    hklm = key "HKLM";
    hkcu = key "HKCU";
    advanced = key "HKCU" ''Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'';
    contentDelivery = key "HKCU" ''Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'';
    on = v: if v then 1 else 0;
    off = v: if v then 0 else 1;
    service = name: startType: v: {
      services.${name} =
        if v then
          { inherit startType; }
        else
          {
            startType = "disabled";
            state = "stopped";
          };
    };
    tasks = names: v: {
      scheduledTasks = lib.genAttrs names (_: {
        enable = v;
      });
    };
    tweak = {
      bool = description: apply: {
        type = types.bool;
        inherit description apply;
      };
      enum = description: values: apply: {
        type = types.enum (builtins.attrNames values);
        inherit description;
        apply = v: apply values.${v};
      };
    };
  };

  groups =
    lib.mapAttrs' (file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import ./${file} helpers))
      (
        lib.filterAttrs (
          file: type: type == "regular" && lib.hasSuffix ".nix" file && file != "default.nix"
        ) (builtins.readDir ./.)
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
