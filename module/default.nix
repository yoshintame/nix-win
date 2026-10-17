{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.windows;
  checks = import ./checks.nix { inherit lib cfg; };
  failed = map (check: check.message) (lib.filter (check: !check.assertion) checks);
in
{
  imports = [
    ./options.nix
    ./defaults
  ];

  config = lib.mkIf cfg.enable {
    assertions = checks;
    windows.build.toplevel = lib.throwIf (failed != [ ]) (lib.concatStringsSep "\n" failed) (
      import ./render { inherit lib pkgs cfg; }
    );
    windows.build.rebuild = import ./rebuild {
      inherit pkgs;
      inherit (cfg) flake;
      nix = config.nix.package;
    };
    environment.systemPackages = [ cfg.build.rebuild ];
  };
}
