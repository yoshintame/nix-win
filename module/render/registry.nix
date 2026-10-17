{ lib, cmd }:
let
  inherit (lib)
    concatLists
    concatStringsSep
    hasInfix
    imap1
    mapAttrsToList
    toHexString
    toLower
    ;

  entries =
    keys:
    concatLists (
      mapAttrsToList (
        path: values:
        if values == null then
          [ { inherit path; } ]
        else if values == { } then
          [
            {
              inherit path;
              create = true;
            }
          ]
        else
          mapAttrsToList (name: value: { inherit path name value; }) values
      ) keys
    );

  validate =
    label: e:
    lib.throwIf (e.name or null == "") "nix-win: ${label}: the default value of a key is not supported"
      (
        lib.throwIf (hasInfix "\"" e.path) "nix-win: ${label}: quotes in key paths are not supported" (
          lib.throwIf (
            builtins.isString (e.value or null) && (hasInfix "\n" e.value || hasInfix "\t" e.value)
          ) "nix-win: ${label}: values with line breaks or tabs cannot be verified" e
        )
      );

  regType = v: if builtins.isInt v then "REG_DWORD" else "REG_SZ";
  regData = v: if builtins.isInt v then toString v else cmd.arg v;
  shown = v: if builtins.isInt v then "0x${toLower (toHexString v)}" else v;
in
{
  root,
  label,
  scope,
}:
keys:
let
  items = imap1 (
    i: raw:
    let
      fullLabel = "${label}\\${raw.path}${lib.optionalString (raw ? name) "\\${raw.name}"}";
      e = validate fullLabel raw;
      key = "\"${root}\\${lib.replaceStrings [ "%" ] [ "%%" ] e.path}\"";
      value = lib.optionalString (e ? name) " /v ${cmd.arg e.name}";
      exists = "reg query ${key}${value} >nul 2>&1";
    in
    {
      index = cmd.pad i;
      label = fullLabel;
      apply =
        if e.create or false then
          "reg add ${key} /f >nul 2>&1 || ${cmd.fail fullLabel}"
        else if (e.value or null) == null then
          "${exists} && (reg delete ${key}${value} /f >nul 2>&1 || ${cmd.fail fullLabel})"
        else
          "reg add ${key}${value} /t ${regType e.value} /d ${regData e.value} /f >nul 2>&1 || ${cmd.fail fullLabel}";
      query = lib.optionalString (!(e.create or false)) "reg query ${key}${value}";
      kind = if (e.value or null) == null then "absent" else "value";
      expected = lib.optionalString (
        e.value or null != null
      ) "    ${e.name}    ${regType e.value}    ${shown e.value}";
    }
  ) (entries keys);

  checked = lib.filter (item: item.query != "") items;
in
{
  apply = map (item: item.apply) items;

  verify = [
    "mkdir \"%dir%\" 2>nul"
  ]
  ++ map (item: "${item.query} > \"%dir%\\${item.index}.txt\" 2>nul") checked;

  expected = map (
    item:
    concatStringsSep "\t" [
      scope
      item.index
      item.kind
      item.label
      item.expected
    ]
  ) checked;
}
