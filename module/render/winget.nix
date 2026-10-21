{
  lib,
  cmd,
  cfg,
  stateDir,
}:
let
  packages = lib.imap1 (
    i: id:
    cfg.winget.packages.${id}
    // {
      index = cmd.pad i;
      inherit id;
    }
  ) (builtins.attrNames cfg.winget.packages);
  enabled = packages != [ ];
  run = mode: ''${cmd.powershell "winget.ps1"} ${mode} "${stateDir}" || set failed=1'';
in
{
  inherit enabled;
  flag = lib.optionals enabled [
    ''set "winget="''
    ''if "%~2"=="winget" set "winget=1"''
  ];
  install = lib.optional enabled ''if "%mode%"=="apply" if defined winget ${run "install"}'';
  verify = lib.optional enabled "if defined winget ${run "verify"}";
  operations = map (p: {
    inherit (p) index;
    kind = "present";
    label = "winget ${p.id}";
    line = "";
  }) packages;
  json = builtins.toJSON (
    map (p: {
      Index = p.index;
      Id = p.id;
      Source = p.source;
      Location = p.location;
      Timeout = p.timeout;
    }) packages
  );
}
