{ lib, cmd }:
let
  inherit (lib)
    concatLists
    mapAttrsToList
    optionalString
    toHexString
    toLower
    ;

  encode =
    v:
    if builtins.isInt v then
      {
        type = "REG_DWORD";
        data = toString v;
        shown = "0x${toLower (toHexString v)}";
      }
    else
      {
        type = "REG_SZ";
        data = cmd.arg v;
        shown = v;
      };
in
{ root, label }:
keys:
concatLists (
  mapAttrsToList (
    path: values:
    let
      key = "\"${root}\\${cmd.percent path}\"";
      target = name: "${key}${optionalString (name != null) " /v ${cmd.arg name}"}";
      fullLabel = name: "${label}\\${path}${optionalString (name != null) "\\${name}"}";
      base = name: {
        label = fullLabel name;
        query = "reg query ${target name}";
      };
      add = name: data: "reg add ${target name}${data} /f >nul 2>&1 || ${cmd.fail (fullLabel name)}";

      delete =
        name:
        base name
        // {
          kind = "absent";
          line = "";
          apply = "reg query ${target name} >nul 2>&1 && (reg delete ${target name} /f >nul 2>&1 || ${cmd.fail (fullLabel name)})";
        };
      present = base null // {
        kind = "present";
        line = "";
        apply = add null "";
      };
      value =
        name: v:
        let
          e = encode v;
        in
        base name
        // {
          kind = "value";
          line = "    ${name}    ${e.type}    ${e.shown}";
          apply = add name " /t ${e.type} /d ${e.data}";
        };
    in
    if values == null then
      [ (delete null) ]
    else if values == { } then
      [ present ]
    else
      mapAttrsToList (name: v: if v == null then delete name else value name v) values
  ) keys
)
