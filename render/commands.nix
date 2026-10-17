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
  inherit (cmd) fail quote;

  entries = imap1 (i: target: {
    inherit target;
    stored = "files/${cmd.pad i}";
    changed = "changed_${cmd.pad i}";
    spec = cfg.files.${target};
  }) (builtins.attrNames cfg.files);
in
{
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
  ) entries;

  capabilities = map (
    c:
    "dism /online /get-capabilityinfo /capabilityname:${c} | find \"State : Installed\" >nul || (dism /online /add-capability /capabilityname:${c} /norestart >nul || ${fail "capability ${c}"})"
  ) cfg.capabilities;

  files = concatMap (
    f:
    let
      src = "\"%~dp0${cmd.winPath f.stored}\"";
      dst = quote f.target;
      grants = concatMapStrings (g: "/grant ${g} ") f.spec.grants;
    in
    [
      "if not exist ${quote (cmd.winDir f.target)} mkdir ${quote (cmd.winDir f.target)}"
      "fc /b ${src} ${dst} >nul 2>&1 || (copy /y ${src} ${dst} >nul && set ${f.changed}=1 || ${fail f.target})"
    ]
    ++ optional (
      f.spec.grants != [ ]
    ) "icacls ${dst} /inheritance:r ${grants}>nul || ${fail "acl ${f.target}"}"
  ) entries;

  onChange = concatMap (
    f:
    optionals (f.spec.onChange != "") (
      [ "if not defined ${f.changed} goto after_${f.changed}" ]
      ++ filter (l: l != "") (lib.splitString "\n" f.spec.onChange)
      ++ [ ":after_${f.changed}" ]
    )
  ) entries;

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

  firewall = concatLists (
    mapAttrsToList (
      name: r:
      let
        args = concatStringsSep " " (
          [
            "dir=${r.direction}"
            "action=${r.action}"
            "protocol=${r.protocol}"
            "enable=${if r.enable then "yes" else "no"}"
          ]
          ++ optional (r.localPort != null) "localport=${toString r.localPort}"
          ++ optional (r.remoteAddress != [ ]) "remoteip=${concatStringsSep "," r.remoteAddress}"
          ++ optional (r.program != null) "program=${quote r.program}"
        );
      in
      [
        "netsh advfirewall firewall delete rule name=${quote name} >nul 2>&1"
        "netsh advfirewall firewall add rule name=${quote name} ${args} >nul || ${fail "firewall ${name}"}"
      ]
    ) cfg.firewall.rules
  );

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
      params = concatStringsSep " " (
        mapAttrsToList (n: v: "-${n} ${v}") cfg.networkAdapters.powerManagement
      );
    in
    "powershell -NoProfile -Command \"Get-NetAdapter -Physical | Where-Object MediaType -eq '802.3' | Set-NetAdapterPowerManagement ${params}\" || ${fail "network adapter power management"}"
  );
}
