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
    imap1
    mapAttrsToList
    optional
    optionals
    ;
  inherit (cmd) fail quote psString;

  winDir = path: concatStringsSep "\\" (lib.init (lib.splitString "\\" path));
  psHashtable =
    attrs: "@{ ${concatStringsSep "; " (mapAttrsToList (name: value: "${name} = ${value}") attrs)} }";
  psArray = values: "@(${concatStringsSep ", " (map psString values)})";

  files = imap1 (i: target: {
    inherit target;
    stored = "files\\${cmd.pad i}";
    changed = "changed_${cmd.pad i}";
    inherit (cfg.files.${target}) text grants onChange;
  }) (builtins.attrNames cfg.files);
in
{
  fileOutputs = lib.listToAttrs (
    map (f: lib.nameValuePair (lib.replaceStrings [ "\\" ] [ "/" ] f.stored) f.text) files
  );

  powershell =
    map (c: {
      label = "capability ${c}";
      body = "if ((Get-WindowsCapability -Online -Name ${psString c}).State -ne 'Installed') { Add-WindowsCapability -Online -Name ${psString c} | Out-Null }";
    }) cfg.capabilities
    ++ mapAttrsToList (
      name: r:
      let
        params = psHashtable (
          {
            Direction = psString r.direction;
            Action = psString r.action;
            Protocol = psString r.protocol;
            Enabled = psString (if r.enable then "True" else "False");
          }
          // lib.optionalAttrs (r.localPort != null) { LocalPort = psString (toString r.localPort); }
          // lib.optionalAttrs (r.remoteAddress != [ ]) { RemoteAddress = psArray r.remoteAddress; }
          // lib.optionalAttrs (r.interfaceAlias != null) { InterfaceAlias = psString r.interfaceAlias; }
        );
      in
      {
        label = "firewall ${name}";
        body = lib.concatStringsSep "\n" [
          "$n = ${psString name}; $d = ${psString r.displayName}; $p = ${params}"
          "if (Get-NetFirewallRule -Name $n -ErrorAction SilentlyContinue) { Set-NetFirewallRule -Name $n -NewDisplayName $d @p } else { New-NetFirewallRule -Name $n -DisplayName $d @p | Out-Null }"
          "Get-NetFirewallRule -DisplayName ([WildcardPattern]::Escape($d)) -ErrorAction SilentlyContinue | Where-Object Name -ne $n | Remove-NetFirewallRule"
        ];
      }
    ) cfg.firewall.rules
    ++ optional (cfg.networkAdapters.powerManagement != { }) {
      label = "network adapter power management";
      body = lib.concatStringsSep "\n" [
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

  files = concatMap (
    f:
    let
      src = "\"%~dp0${f.stored}\"";
      dst = quote f.target;
      grants = concatMapStrings (g: " /grant:r ${g}") f.grants;
    in
    [
      "if not exist ${quote (winDir f.target)} mkdir ${quote (winDir f.target)}"
      "fc /b ${src} ${dst} >nul 2>&1 || (copy /y ${src} ${dst} >nul && set ${f.changed}=1 || ${fail f.target})"
    ]
    ++
      optional (f.grants != [ ])
        "icacls ${dst} /reset >nul && icacls ${dst} /inheritance:r${grants} >nul && icacls ${dst} /setowner *S-1-5-32-544 >nul || ${fail "acl ${f.target}"}"
    ++ optionals (f.onChange != "") (
      [ "if not defined ${f.changed} goto after_${f.changed}" ]
      ++ map (line: "${line} || ${fail "on change of ${f.target}"}") (
        filter (l: l != "") (lib.splitString "\n" f.onChange)
      )
      ++ [ ":after_${f.changed}" ]
    )
  ) files;

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
