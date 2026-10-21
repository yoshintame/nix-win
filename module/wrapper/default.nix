{
  pkgs,
  bundleFile,
  declared,
}:
pkgs.writeShellApplication {
  name = "winget";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
  ];
  runtimeEnv = {
    NIX_WIN_BUNDLE_FILE = bundleFile;
    NIX_WIN_DECLARED = builtins.concatStringsSep "\n" declared;
  };
  excludeShellChecks = [ "SC2016" ];
  text = builtins.readFile ./winget.sh;
}
