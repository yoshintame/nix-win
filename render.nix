{
  lib,
  pkgs,
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
    optionals
    removePrefix
    replaceStrings
    toLower
    toUpper
    ;

  crlf = concatMapStrings (line: line + "\r\n");

  hex = n: toLower (lib.toHexString n);
  hex2 = n: fixedWidthString 2 "0" (hex n);
  hexBytes = bytes: concatStringsSep "," (map hex2 bytes);
  pow256 = i: lib.foldl' (acc: _: acc * 256) 1 (lib.range 1 i);
  littleEndian = width: n: builtins.genList (i: lib.mod (n / pow256 i) 256) width;

  utf16 =
    s:
    concatMap (
      c:
      let
        code = lib.strings.charToInt c;
      in
      if code > 127 then
        throw "nix-windows: only ASCII is supported in '${s}'"
      else
        [
          code
          0
        ]
    ) (lib.stringToCharacters s);

  escapeReg = replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ];
  quoteCmd = s: "\"${replaceStrings [ "%" ] [ "%%" ] s}\"";
  escapeEcho =
    replaceStrings
      [
        "^"
        "&"
        "|"
        "<"
        ">"
        "("
        ")"
        "%"
      ]
      [
        "^^"
        "^&"
        "^|"
        "^<"
        "^>"
        "^("
        "^)"
        "%%"
      ];
  winPath = replaceStrings [ "/" ] [ "\\" ];
  winDir = p: concatStringsSep "\\" (lib.init (lib.splitString "\\" p));
  pad = fixedWidthString 4 "0";

  fail = label: "(echo FAILED ${escapeEcho label} & set failed=1)";

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
      data = "hex(2):${
        hexBytes (
          utf16 s
          ++ [
            0
            0
          ]
        )
      }";
      type = "REG_EXPAND_SZ";
      shown = s;
    };
    multi = l: {
      data = "hex(7):${
        hexBytes (
          concatMap (
            s:
            utf16 s
            ++ [
              0
              0
            ]
          ) l
          ++ [
            0
            0
          ]
        )
      }";
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
      shown = toUpper (concatMapStrings hex2 bytes);
    };
  };

  encode =
    v:
    if v == null then
      null
    else if builtins.isInt v then
      dword v
    else if builtins.isString v then
      sz v
    else if (v._type or null) == "regValue" then
      tagged.${v.type} v.value
    else
      throw "nix-windows: unsupported registry value ${builtins.toJSON v}";

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

  mkScope = id: regRoot: queryRoot: tree: deleted: rec {
    inherit id;
    sections =
      map (key: {
        label = "${queryRoot}\\${concatStringsSep "\\" key.path}";
        lines = [
          "[${regRoot}\\${concatStringsSep "\\" key.path}]"
        ]
        ++ mapAttrsToList (
          name: v:
          let
            e = encode v;
          in
          "${if name == "" then "@" else "\"${escapeReg name}\""}=${if e == null then "-" else e.data}"
        ) key.values;
      }) (keysOf tree)
      ++ map (key: {
        label = "-${queryRoot}\\${key}";
        lines = [ "[-${regRoot}\\${key}]" ];
      }) deleted;

    regFiles = imap1 (i: section: {
      path = "${id}/${pad (toString i)}.reg";
      encoding = "utf16";
      text = crlf (
        [
          "Windows Registry Editor Version 5.00"
          ""
        ]
        ++ section.lines
        ++ [ "" ]
      );
      inherit (section) label;
    }) sections;

    imports = map (f: "reg import \"%~dp0${winPath f.path}\" >nul 2>&1 || ${fail f.label}") regFiles;

    checks =
      let
        valueChecks = concatMap (
          key:
          let
            keyLabel = "${queryRoot}\\${concatStringsSep "\\" key.path}";
          in
          mapAttrsToList (
            name: v:
            let
              e = encode v;
              shownName = if name == "" then "(Default)" else name;
            in
            {
              label = "${keyLabel}\\${shownName}";
              query = "reg query ${quoteCmd keyLabel} ${if name == "" then "/ve" else "/v ${quoteCmd name}"}";
              kind = if e == null then "absent" else "value";
              expected = if e == null then "" else "    ${shownName}    ${e.type}    ${e.shown}";
            }
          ) key.values
        ) (keysOf tree);
        keyChecks = map (key: {
          label = "${queryRoot}\\${key}";
          query = "reg query ${quoteCmd "${queryRoot}\\${key}"}";
          kind = "absent";
          expected = "";
        }) deleted;
        checkable =
          c:
          !(
            hasInfix "\n" c.expected
            || hasInfix "\t" c.expected
            || hasInfix "\t" c.label
            || hasInfix "\"" c.label
          );
      in
      imap1 (i: c: c // { index = pad (toString i); }) (filter checkable (valueChecks ++ keyChecks));

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

  users = builtins.attrNames cfg.users;

  machine = mkScope "machine" "HKEY_LOCAL_MACHINE" "HKLM" cfg.registry.HKLM (deletedUnder "HKLM");
  userScope =
    name: mkScope "user-${name}" "HKEY_CURRENT_USER" "HKCU" (userTree name) (deletedUnder "HKCU");
  hiveScope =
    name:
    mkScope "hive-${name}" "HKEY_USERS\\lasthaze-${name}" "HKU\\lasthaze-${name}" (userTree name) (
      deletedUnder "HKCU"
    );

  scopes = [
    machine
  ]
  ++ concatMap (name: [
    (userScope name)
    (hiveScope name)
  ]) users;

  fileEntries = imap1 (i: target: {
    inherit target;
    stored = "files/${pad (toString i)}";
    spec = cfg.files.${target};
  }) (builtins.attrNames cfg.files);

  fileOutputs = map (
    f:
    if f.spec.source != null then
      {
        path = f.stored;
        encoding = "copy";
        source = "${f.spec.source}";
      }
    else
      {
        path = f.stored;
        encoding = "utf8";
        inherit (f.spec) text;
      }
  ) fileEntries;

  fileCommands = concatMap (
    f:
    let
      src = "\"%~dp0${winPath f.stored}\"";
      dst = quoteCmd f.target;
      changed = "changed_${baseNameOf f.stored}";
    in
    [
      "if not exist ${quoteCmd (winDir f.target)} mkdir ${quoteCmd (winDir f.target)}"
      "fc /b ${src} ${dst} >nul 2>&1 || (copy /y ${src} ${dst} >nul && set ${changed}=1 || ${fail f.target})"
    ]
    ++
      optional (f.spec.grants != [ ])
        "icacls ${dst} /inheritance:r ${
          concatMapStrings (g: "/grant ${g} ") f.spec.grants
        }>nul || ${fail "acl ${f.target}"}"
  ) fileEntries;

  onChangeCommands = concatMap (
    f:
    let
      changed = "changed_${baseNameOf f.stored}";
      skip = "after_${changed}";
    in
    optionals (f.spec.onChange != "") (
      [ "if not defined ${changed} goto ${skip}" ]
      ++ filter (l: l != "") (lib.splitString "\n" f.spec.onChange)
      ++ [ ":${skip}" ]
    )
  ) fileEntries;

  capabilityCommands = map (
    c:
    "dism /online /get-capabilityinfo /capabilityname:${c} | find \"State : Installed\" >nul || (dism /online /add-capability /capabilityname:${c} /norestart >nul || ${fail "capability ${c}"})"
  ) cfg.capabilities;

  serviceCommands = concatLists (
    mapAttrsToList (
      name: s:
      let
        q = quoteCmd name;
      in
      optional (
        s.startType != null
      ) "sc config ${q} start= ${s.startType} >nul || ${fail "service ${name} start=${s.startType}"}"
      ++
        optional (s.state == "running")
          "sc query ${q} | find \"RUNNING\" >nul || (net start ${q} >nul 2>&1 || ${fail "service ${name} start"})"
      ++
        optional (s.state == "stopped")
          "sc query ${q} | find \"STOPPED\" >nul || (net stop ${q} >nul 2>&1 || ${fail "service ${name} stop"})"
    ) cfg.services
  );

  firewallCommands = concatLists (
    mapAttrsToList (
      name: r:
      let
        q = quoteCmd name;
        args = concatStringsSep " " (
          [
            "dir=${r.direction}"
            "action=${r.action}"
            "protocol=${r.protocol}"
            "enable=${if r.enable then "yes" else "no"}"
          ]
          ++ optional (r.localPort != null) "localport=${toString r.localPort}"
          ++ optional (r.remoteAddress != [ ]) "remoteip=${concatStringsSep "," r.remoteAddress}"
          ++ optional (r.program != null) "program=${quoteCmd r.program}"
        );
      in
      [
        "netsh advfirewall firewall delete rule name=${q} >nul 2>&1"
        "netsh advfirewall firewall add rule name=${q} ${args} >nul || ${fail "firewall ${name}"}"
      ]
    ) cfg.firewall.rules
  );

  powerCommands =
    mapAttrsToList (
      name: value: "powercfg /change ${name} ${toString value} >nul || ${fail "powercfg ${name}"}"
    ) cfg.power.timeouts
    ++ optional (cfg.power.hibernate != null) (
      let
        state = if cfg.power.hibernate then "on" else "off";
      in
      "powercfg /hibernate ${state} >nul || ${fail "powercfg hibernate ${state}"}"
    );

  taskCommands = mapAttrsToList (
    name: t:
    let
      q = quoteCmd name;
      flag = if t.enable then "/Enable" else "/Disable";
    in
    "schtasks /Query /TN ${q} >nul 2>&1 && (schtasks /Change /TN ${q} ${flag} >nul 2>&1 || ${fail "task ${name}"}) || echo skip task ${escapeEcho name}: not found"
  ) cfg.scheduledTasks;

  adapterCommands = optional (cfg.networkAdapters.powerManagement != { }) (
    let
      params = concatStringsSep " " (
        mapAttrsToList (n: v: "-${n} ${v}") cfg.networkAdapters.powerManagement
      );
    in
    "powershell -NoProfile -Command \"Get-NetAdapter -Physical | Where-Object MediaType -eq '802.3' | Set-NetAdapterPowerManagement ${params}\" || ${fail "network adapter power management"}"
  );

  hiveFile = name: hive: {
    path = "hive-${name}.cmd";
    encoding = "utf8";
    text = crlf (
      [
        "@echo off"
        "chcp 65001 >nul"
        "reg load ${quoteCmd "HKU\\lasthaze-${name}"} ${quoteCmd "${cfg.users.${name}.profile}\\NTUSER.DAT"} >nul 2>&1"
        "if errorlevel 1 (echo skip ${escapeEcho name}: hive in use & exit /b 0)"
        "if /i not \"%~1\"==\"apply\" goto verify"
      ]
      ++ hive.imports
      ++ [ ":verify" ]
      ++ hive.queries
      ++ [
        "reg unload ${quoteCmd "HKU\\lasthaze-${name}"} >nul 2>&1 || ${fail "unload HKU\\lasthaze-${name}"}"
      ]
    );
  };

  applyFile = {
    path = "apply.cmd";
    encoding = "utf8";
    text = crlf (
      [
        "@echo off"
        "setlocal"
        "chcp 65001 >nul"
        "set failed=0"
      ]
      ++ capabilityCommands
      ++ fileCommands
      ++ machine.imports
      ++ serviceCommands
      ++ firewallCommands
      ++ powerCommands
      ++ taskCommands
      ++ adapterCommands
      ++ map (
        name:
        "if /i \"%USERNAME%\"==${quoteCmd name} (call \"%~dp0user-${name}.cmd\") else (call \"%~dp0hive-${name}.cmd\" apply)"
      ) users
      ++ onChangeCommands
      ++ [ "exit /b %failed%" ]
    );
  };

  cmdFile = path: body: {
    inherit path;
    encoding = "utf8";
    text = crlf (
      [
        "@echo off"
        "setlocal"
        "chcp 65001 >nul"
        "set failed=0"
      ]
      ++ body
      ++ [ "exit /b %failed%" ]
    );
  };

  outputs = [
    applyFile
    (cmdFile "verify-machine.cmd" machine.queries)
    {
      path = "expected.tsv";
      encoding = "utf8";
      text = concatMapStrings (l: l + "\n") (concatMap (s: s.expected) scopes);
    }
    {
      path = "users";
      encoding = "utf8";
      text = concatMapStrings (u: u + "\n") users;
    }
  ]
  ++ concatMap (s: s.regFiles) scopes
  ++ concatMap (
    name:
    let
      user = userScope name;
    in
    [
      {
        path = "user-${name}.cmd";
        encoding = "utf8";
        text = crlf ([ "@echo off" ] ++ user.imports);
      }
      (cmdFile "verify-user-${name}.cmd" user.queries)
      (hiveFile name (hiveScope name))
    ]
  ) users
  ++ fileOutputs;
in
pkgs.runCommand "nix-windows"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.iconv
    ];
    spec = builtins.toJSON (map (o: removeAttrs o [ "label" ]) outputs);
    passAsFile = [ "spec" ];
  }
  ''
    mkdir -p "$out"
    n=$(jq length "$specPath")
    for ((i = 0; i < n; i++)); do
      path=$(jq -r ".[$i].path" "$specPath")
      mkdir -p "$out/$(dirname "$path")"
      case $(jq -r ".[$i].encoding" "$specPath") in
        utf16) { printf '\xff\xfe'; jq -j ".[$i].text" "$specPath" | iconv -f UTF-8 -t UTF-16LE; } > "$out/$path" ;;
        copy) cp "$(jq -r ".[$i].source" "$specPath")" "$out/$path" ;;
        *) jq -j ".[$i].text" "$specPath" > "$out/$path" ;;
      esac
    done
  ''
