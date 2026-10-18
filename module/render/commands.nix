{
  lib,
  cmd,
  cfg,
}:
let
  inherit (lib)
    concatLists
    concatMapStrings
    concatStringsSep
    filter
    imap1
    mapAttrsToList
    optional
    optionals
    ;
  inherit (cmd)
    fail
    failReturn
    quote
    psArray
    psHashtable
    psString
    ;

  winDir = path: concatStringsSep "\\" (lib.init (lib.splitString "\\" path));

  entries = imap1 (i: target: {
    inherit target;
    id = cmd.pad i;
    pending = "\"%ProgramData%\\nix-win\\pending\\${
      builtins.substring 0 16 (builtins.hashString "sha256" (lib.toLower target))
    }\"";
    onChange = filter (l: l != "") (lib.splitString "\n" cfg.files.${target}.onChange);
    inherit (cfg.files.${target}) text grants validate;
  }) (builtins.attrNames cfg.files);
in
{
  powershell =
    map (c: {
      label = "capability ${c}";
      body = "if ((Get-WindowsCapability -Online -Name ${psString c}).State -ne 'Installed') { Add-WindowsCapability -Online -Name ${psString c} | Out-Null }";
    }) cfg.capabilities
    ++ mapAttrsToList (
      name: r:
      let
        params = psHashtable {
          Direction = psString r.direction;
          Action = psString r.action;
          Protocol = psString r.protocol;
          Enabled = psString (if r.enable then "True" else "False");
          LocalPort = psString (if r.localPort == null then "Any" else toString r.localPort);
          RemoteAddress = if r.remoteAddress == [ ] then psString "Any" else psArray r.remoteAddress;
          InterfaceAlias = psString (if r.interfaceAlias == null then "Any" else r.interfaceAlias);
        };
      in
      {
        label = "firewall ${name}";
        body = concatStringsSep "\n" [
          "$n = ${psString name}; $d = ${psString r.displayName}; $p = ${params}"
          "if (Get-NetFirewallRule -Name $n -ErrorAction SilentlyContinue) { Set-NetFirewallRule -Name $n -NewDisplayName $d @p } else { New-NetFirewallRule -Name $n -DisplayName $d @p | Out-Null }"
          "Get-NetFirewallRule -DisplayName ([WildcardPattern]::Escape($d)) -ErrorAction SilentlyContinue | Where-Object Name -ne $n | Remove-NetFirewallRule"
        ];
      }
    ) cfg.firewall.rules
    ++ optional (cfg.networkAdapters.powerManagement != { }) {
      label = "network adapter power management";
      body = concatStringsSep "\n" [
        "$d = ${psHashtable (lib.mapAttrs (_: psString) cfg.networkAdapters.powerManagement)}"
        "Get-NetAdapter -Physical | Where-Object MediaType -eq '802.3' | Get-NetAdapterPowerManagement | ForEach-Object {"
        "  $a = $_; $p = @{}"
        "  foreach ($k in $d.Keys) { if ($a.$k -ne 'Unsupported' -and $a.$k -ne $d[$k]) { $p[$k] = $d[$k] } }"
        "  if ($p.Count) { Set-NetAdapterPowerManagement -Name $a.Name @p }"
        "}"
      ];
    };

  services = concatLists (
    mapAttrsToList (
      name: s:
      let
        q = quote name;
        ensure =
          state: verb:
          "sc query ${q} | find \"${state}\" >nul || (net ${verb} ${q} >nul 2>&1 || ${fail "service ${name} ${verb}"})";
      in
      optional (
        s.startType != null
      ) "sc config ${q} start= ${s.startType} >nul || ${fail "service ${name} start=${s.startType}"}"
      ++ optional (s.state == "running") (ensure "RUNNING" "start")
      ++ optional (s.state == "stopped") (ensure "STOPPED" "stop")
    ) cfg.services
  );

  files = map (
    f:
    let
      label = "file_${f.id}";
      src = "\"%~dp0files\\${f.id}\"";
      dst = quote f.target;
      grants = concatMapStrings (g: " /grant:r ${g}") f.grants;
      hasOnChange = f.onChange != [ ];
    in
    {
      inherit label;
      output."files/${f.id}" = f.text;
      body = concatLists [
        [
          "if not exist ${quote (winDir f.target)} mkdir ${quote (winDir f.target)}"
          "fc /b ${src} ${dst} >nul 2>&1 && goto ${label}_installed"
        ]
        (optional (f.validate != null) "${f.validate src} || ${failReturn "validate ${f.target}"}")
        (optionals hasOnChange [
          "if not exist \"%ProgramData%\\nix-win\\pending\" mkdir \"%ProgramData%\\nix-win\\pending\""
          "type nul > ${f.pending} || ${failReturn "pending ${f.target}"}"
        ])
        [
          "copy /y ${src} ${dst} >nul || ${failReturn f.target}"
          ":${label}_installed"
        ]
        (optional (f.grants != [ ])
          "icacls ${dst} /reset >nul && icacls ${dst} /inheritance:r${grants} >nul && icacls ${dst} /setowner *S-1-5-32-544 >nul || ${fail "acl ${f.target}"}"
        )
        (optionals hasOnChange (
          [ "if not exist ${f.pending} exit /b 0" ]
          ++ map (line: "${line} || ${failReturn "on change of ${f.target}"}") f.onChange
          ++ [ "del ${f.pending}" ]
        ))
      ];
    }
  ) entries;

  power =
    mapAttrsToList (
      name: value: "powercfg /change ${name} ${toString value} >nul || ${fail "powercfg ${name}"}"
    ) cfg.power.timeouts
    ++ optional (cfg.power.hibernate != null) (
      let
        state = if cfg.power.hibernate then "on" else "off";
      in
      "powercfg /hibernate ${state} >nul || ${fail "powercfg hibernate ${state}"}"
    );

  tasks = mapAttrsToList (
    name: t:
    let
      q = quote name;
      flag = if t.enable then "/Enable" else "/Disable";
    in
    "schtasks /Query /TN ${q} >nul 2>&1 && (schtasks /Change /TN ${q} ${flag} >nul 2>&1 || ${fail "task ${name}"}) || echo skip task ${cmd.escapeEcho name}: not found"
  ) cfg.scheduledTasks;

}
