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

  capabilities = map (
    c:
    cmd.powershell "if ((Get-WindowsCapability -Online -Name ${psString c}).State -ne 'Installed') { Add-WindowsCapability -Online -Name ${psString c} -ErrorAction Stop | Out-Null }" "capability ${c}"
  ) cfg.capabilities;

  firewall = mapAttrsToList (
    name: r:
    let
      params = concatStringsSep " " (
        [
          "-Name ${psString name}"
          "-DisplayName ${psString r.displayName}"
          "-Direction ${r.direction}"
          "-Action ${r.action}"
          "-Protocol ${r.protocol}"
          "-Enabled ${if r.enable then "True" else "False"}"
        ]
        ++ optional (r.localPort != null) "-LocalPort ${toString r.localPort}"
        ++ optional (r.remoteAddress != [ ]) "-RemoteAddress ${concatStringsSep "," r.remoteAddress}"
      );
    in
    cmd.powershell "Get-NetFirewallRule -Name ${psString name} -ErrorAction SilentlyContinue | Remove-NetFirewallRule; Get-NetFirewallRule -DisplayName ${psString r.displayName} -ErrorAction SilentlyContinue | Remove-NetFirewallRule; New-NetFirewallRule ${params} -ErrorAction Stop | Out-Null" "firewall ${name}"
  ) cfg.firewall.rules;

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
      grants = concatMapStrings (g: "/grant ${g} ") f.grants;
    in
    [
      "if not exist ${quote (winDir f.target)} mkdir ${quote (winDir f.target)}"
      "fc /b ${src} ${dst} >nul 2>&1 || (copy /y ${src} ${dst} >nul && set ${f.changed}=1 || ${fail f.target})"
    ]
    ++ optional (
      f.grants != [ ]
    ) "icacls ${dst} /inheritance:r ${grants}>nul || ${fail "acl ${f.target}"}"
  ) files;

  onChange = concatMap (
    f:
    optionals (f.onChange != "") (
      [ "if not defined ${f.changed} goto after_${f.changed}" ]
      ++ filter (l: l != "") (lib.splitString "\n" f.onChange)
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

  adapters = optional (cfg.networkAdapters.powerManagement != { }) (
    let
      pm = cfg.networkAdapters.powerManagement;
      drift = concatStringsSep " -or " (mapAttrsToList (n: v: "$_.${n} -ne ${psString v}") pm);
      params = concatStringsSep " " (mapAttrsToList (n: v: "-${n} ${v}") pm);
    in
    cmd.powershell "Get-NetAdapter -Physical | Where-Object MediaType -eq '802.3' | Get-NetAdapterPowerManagement | Where-Object { ${drift} } | ForEach-Object { Set-NetAdapterPowerManagement -Name $_.Name ${params} -ErrorAction Stop }" "network adapter power management"
  );
}
