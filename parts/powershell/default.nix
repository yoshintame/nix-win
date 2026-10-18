pkgs:
let
  psscriptanalyzer = pkgs.fetchzip {
    name = "psscriptanalyzer-1.25.0";
    url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/1.25.0";
    extension = "zip";
    stripRoot = false;
    hash = "sha256-OEyOGPyFatNo68Jlx1G8UOKQu83UScZMRQ3TlzKxjl0=";
  };
  run =
    name: script:
    pkgs.writeShellScriptBin "powershell-${name}" ''
      HOME=$(mktemp -d)
      export HOME POWERSHELL_TELEMETRY_OPTOUT=1
      exec ${pkgs.powershell}/bin/pwsh -NoProfile -NonInteractive -File ${script} ${psscriptanalyzer} ${./settings.psd1} "$@"
    '';
in
{
  format = run "format" ./format.ps1;
  analyze = run "analyze" ./analyze.ps1;
}
