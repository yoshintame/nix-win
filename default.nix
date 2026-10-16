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
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    windows.build.toplevel = import ./render.nix { inherit lib pkgs cfg; };
    environment.systemPackages = [
      (import ./windows-rebuild.nix {
        inherit pkgs;
        inherit (cfg) flake;
      })
    ];
  };
}
