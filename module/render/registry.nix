{ lib, cmd }:
let
  inherit (lib)
    concatLists
    mapAttrsToList
    optionalString
    toHexString
    toLower
    ;

  regType = v: if builtins.isInt v then "REG_DWORD" else "REG_SZ";
  regData = v: if builtins.isInt v then toString v else cmd.arg v;
  shown = v: if builtins.isInt v then "0x${toLower (toHexString v)}" else v;
in
{ root, label }:
keys:
concatLists (
  mapAttrsToList (
    path: values:
    let
      key = "\"${root}\\${cmd.percent path}\"";
      operation =
        name: value:
        let
          target = "${key}${optionalString (name != null) " /v ${cmd.arg name}"}";
          fullLabel = "${label}\\${path}${optionalString (name != null) "\\${name}"}";
          query = "reg query ${target}";
          add = data: "reg add ${target}${data} /f >nul 2>&1 || ${cmd.fail fullLabel}";
        in
        {
          label = fullLabel;
          inherit query;
        }
        // (
          if value == null then
            {
              kind = "absent";
              line = "";
              apply = "${query} >nul 2>&1 && (reg delete ${target} /f >nul 2>&1 || ${cmd.fail fullLabel})";
            }
          else if value == { } then
            {
              kind = "present";
              line = "";
              apply = add "";
            }
          else
            {
              kind = "value";
              line = "    ${name}    ${regType value}    ${shown value}";
              apply = add " /t ${regType value} /d ${regData value}";
            }
        );
    in
    if values == null || values == { } then
      [ (operation null values) ]
    else
      mapAttrsToList operation values
  ) keys
)
