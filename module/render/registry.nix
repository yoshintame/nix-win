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
        name: kind: apply: line:
        let
          value = optionalString (name != null) " /v ${cmd.arg name}";
          fullLabel = "${label}\\${path}${optionalString (name != null) "\\${name}"}";
        in
        {
          inherit kind line;
          label = fullLabel;
          query = "reg query ${key}${value}";
          apply =
            if apply == "delete" then
              "reg query ${key}${value} >nul 2>&1 && (reg delete ${key}${value} /f >nul 2>&1 || ${cmd.fail fullLabel})"
            else
              "reg add ${key}${value}${apply} /f >nul 2>&1 || ${cmd.fail fullLabel}";
        };
    in
    if values == null then
      [ (operation null "absent" "delete" "") ]
    else if values == { } then
      [ (operation null "present" "" "") ]
    else
      mapAttrsToList (
        name: v:
        if v == null then
          operation name "absent" "delete" ""
        else
          operation name "value" " /t ${regType v} /d ${regData v}"
            "    ${name}    ${regType v}    ${shown v}"
      ) values
  ) keys
)
