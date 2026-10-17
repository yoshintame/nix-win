{
  lib,
  cmd,
  cfg,
}:
let
  inherit (lib)
    concatLists
    concatMap
    concatMapStrings
    concatStringsSep
    filter
    filterAttrs
    fixedWidthString
    hasInfix
    hasPrefix
    imap1
    mapAttrsToList
    optional
    removePrefix
    replaceStrings
    toLower
    ;

  hex = n: toLower (lib.toHexString n);
  hex2 = n: fixedWidthString 2 "0" (hex n);
  hexBytes = bytes: concatStringsSep "," (map hex2 bytes);
  pow256 = i: lib.foldl' (acc: _: acc * 256) 1 (lib.range 1 i);
  littleEndian = width: n: builtins.genList (i: lib.mod (n / pow256 i) 256) width;

  nul = lib.replicate 2 0;
  charCode =
    c:
    let
      code = lib.strings.charToInt c;
    in
    if code > 127 then throw "nix-windows: only ASCII is supported, got '${c}'" else code;
  utf16 = s: concatMap (c: [ (charCode c) ] ++ [ 0 ]) (lib.stringToCharacters s);
  utf16z = s: utf16 s ++ nul;

  escapeReg = replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ];

  isValue = v: !(builtins.isAttrs v) || v ? _type;

  dword =
    n:
    assert lib.assertMsg (
      builtins.isInt n && n >= 0 && n <= 4294967295
    ) "nix-windows: DWORD out of range: ${toString n}";
    {
      data = "dword:${fixedWidthString 8 "0" (hex n)}";
      type = "REG_DWORD";
      shown = "0x${hex n}";
    };

  sz = s: {
    data = "\"${escapeReg s}\"";
    type = "REG_SZ";
    shown = s;
  };

  tagged = {
    inherit dword sz;
    expand = s: {
      data = "hex(2):${hexBytes (utf16z s)}";
      type = "REG_EXPAND_SZ";
      shown = s;
    };
    multi = l: {
      data = "hex(7):${hexBytes (concatMap utf16z l ++ nul)}";
      type = "REG_MULTI_SZ";
      shown = concatStringsSep "\\0" l;
    };
    qword = n: {
      data = "hex(b):${hexBytes (littleEndian 8 n)}";
      type = "REG_QWORD";
      shown = "0x${hex n}";
    };
    binary = bytes: {
      data = "hex:${hexBytes bytes}";
      type = "REG_BINARY";
      shown = lib.toUpper (concatMapStrings hex2 bytes);
    };
  };

  encoders = {
    null = _: null;
    int = dword;
    string = sz;
    set = v: tagged.${v.type} v.value;
  };

  unsupported = v: throw "nix-windows: unsupported registry value ${builtins.toJSON v}";
  encode = v: (encoders.${builtins.typeOf v} or unsupported) v;

  walk =
    path: node:
    let
      values = filterAttrs (_: isValue) node;
      subkeys = filterAttrs (_: v: !isValue v) node;
    in
    optional (values != { } || subkeys == { }) { inherit path values; }
    ++ concatLists (mapAttrsToList (name: walk (path ++ [ name ])) subkeys);

  keysOf =
    tree:
    concatLists (
      mapAttrsToList (
        name: node:
        if isValue node then
          throw "nix-windows: registry value '${name}' must be inside a key"
        else
          walk [ name ] node
      ) tree
    );

  deletedUnder =
    root: map (removePrefix "${root}\\") (filter (hasPrefix "${root}\\") cfg.deletedKeys);

  userTree =
    name:
    lib.recursiveUpdateUntil (
      _: l: r:
      isValue l || isValue r
    ) cfg.registry.HKCU cfg.users.${name}.registry;

  valueName = name: if name == "" then "@" else "\"${escapeReg name}\"";
  shownName = name: if name == "" then "(Default)" else name;
  valueQuery = name: if name == "" then "/ve" else "/v ${cmd.quote name}";

  mkScope =
    id: regRoot: queryRoot: tree: deleted:
    let
      keys = keysOf tree;
      keyPath = key: concatStringsSep "\\" key.path;

      sections =
        map (key: {
          label = "${queryRoot}\\${keyPath key}";
          lines = [
            "[${regRoot}\\${keyPath key}]"
          ]
          ++ mapAttrsToList (
            name: v:
            let
              e = encode v;
            in
            "${valueName name}=${if e == null then "-" else e.data}"
          ) key.values;
        }) keys
        ++ map (key: {
          label = "-${queryRoot}\\${key}";
          lines = [ "[-${regRoot}\\${key}]" ];
        }) deleted;

      regFiles = imap1 (i: section: {
        path = "${id}/${cmd.pad i}.reg";
        encoding = "utf16";
        text = cmd.crlf (
          [
            "Windows Registry Editor Version 5.00"
            ""
          ]
          ++ section.lines
          ++ [ "" ]
        );
        inherit (section) label;
      }) sections;

      valueChecks = concatMap (
        key:
        mapAttrsToList (
          name: v:
          let
            e = encode v;
            keyLabel = "${queryRoot}\\${keyPath key}";
          in
          {
            label = "${keyLabel}\\${shownName name}";
            query = "reg query ${cmd.quote keyLabel} ${valueQuery name}";
            kind = if e == null then "absent" else "value";
            expected = if e == null then "" else "    ${shownName name}    ${e.type}    ${e.shown}";
          }
        ) key.values
      ) keys;

      keyChecks = map (key: {
        label = "${queryRoot}\\${key}";
        query = "reg query ${cmd.quote "${queryRoot}\\${key}"}";
        kind = "absent";
        expected = "";
      }) deleted;

      checkable =
        c: !(hasInfix "\n" c.expected || hasInfix "\t" (c.expected + c.label) || hasInfix "\"" c.label);

      checks = imap1 (i: c: c // { index = cmd.pad i; }) (filter checkable (valueChecks ++ keyChecks));
    in
    {
      inherit regFiles;

      imports = map (
        f: "reg import \"%~dp0${cmd.winPath f.path}\" >nul 2>&1 || ${cmd.fail f.label}"
      ) regFiles;

      queries = [
        "mkdir \"%~dp0out\\${id}\" 2>nul"
      ]
      ++ map (c: "${c.query} > \"%~dp0out\\${id}\\${c.index}.txt\" 2>nul") checks;

      expected = map (
        c:
        concatStringsSep "\t" [
          id
          c.index
          c.kind
          c.label
          c.expected
        ]
      ) checks;
    };
in
{
  users = builtins.attrNames cfg.users;

  machine = mkScope "machine" "HKEY_LOCAL_MACHINE" "HKLM" cfg.registry.HKLM (deletedUnder "HKLM");

  user =
    name: mkScope "user-${name}" "HKEY_CURRENT_USER" "HKCU" (userTree name) (deletedUnder "HKCU");

  hive =
    name:
    mkScope "hive-${name}" "HKEY_USERS\\lasthaze-${name}" "HKU\\lasthaze-${name}" (userTree name) (
      deletedUnder "HKCU"
    );
}
