{
  pkgs,
  flake,
  nix,
}:
pkgs.writeShellApplication {
  name = "windows-rebuild";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    nix
  ];
  runtimeEnv = {
    NIX_WIN_FLAKE = flake;
    NIX_WIN_COMPARE = "${./compare.awk}";
  };
  text = builtins.readFile ./windows-rebuild.sh;
}
