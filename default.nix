{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.windows;
in
{
  imports = [
    ./options.nix
    ./defaults
  ];

  config = lib.mkIf cfg.enable {
    windows.build.toplevel = import ./render.nix { inherit lib pkgs cfg; };
    windows.build.rebuild = import ./windows-rebuild.nix {
      inherit pkgs;
      inherit (cfg) flake;
    };
    environment.systemPackages = [ cfg.build.rebuild ];
  };
}
