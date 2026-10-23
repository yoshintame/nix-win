{
  pkgs,
  bundleFile,
  declared,
  installerTypes,
}:
pkgs.writeShellApplication {
  name = "winget";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.util-linux
  ];
  runtimeEnv = {
    NIX_WIN_BUNDLE_FILE = bundleFile;
    NIX_WIN_DECLARED = builtins.concatStringsSep "\n" declared;
    NIX_WIN_INSTALLER_TYPES = builtins.concatStringsSep " " installerTypes;
  };
  excludeShellChecks = [ "SC2016" ];
  text = builtins.readFile ./winget.sh;
}
