{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.windows;
  checks = import ./checks.nix { inherit lib cfg; };
  bundled = if cfg.winget.bundle == null then { } else lib.importJSON cfg.winget.bundle;
  inBundle = id: lib.any (other: lib.toLower other == lib.toLower id) (builtins.attrNames bundled);
in
{
  imports = [
    ./options.nix
    ./defaults
  ];

  config = lib.mkIf cfg.enable {
    windows.winget.packages = bundled;
    assertions = checks;
    windows.build.toplevel = lib.asserts.checkAssertWarn checks [ ] (
      import ./render { inherit lib pkgs cfg; }
    );
    windows.build.rebuild = import ./rebuild {
      inherit pkgs;
      inherit (cfg) flake;
      nix = config.nix.package;
    };
    windows.build.winget = lib.mkIf (cfg.winget.bundleFile != null) (
      import ./wrapper {
        inherit pkgs;
        inherit (cfg.winget) bundleFile;
        declared = builtins.filter (id: !inBundle id) (builtins.attrNames cfg.winget.packages);
      }
    );
    environment.systemPackages = [
      cfg.build.rebuild
    ]
    ++ lib.optional (cfg.winget.bundleFile != null) cfg.build.winget;
  };
}
