{ pkgs, flake }:
pkgs.writeShellApplication {
  name = "windows-rebuild";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
  ];
  runtimeEnv = {
    NIX_WINDOWS_FLAKE = flake;
    NIX_WINDOWS_COMPARE = "${./compare.awk}";
  };
  text = builtins.readFile ./windows-rebuild.sh;
}
