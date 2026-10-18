_: {
  perSystem =
    { config, pkgs, ... }:
    let
      powershell = import ./powershell pkgs;
    in
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt = {
            enable = true;
            package = pkgs.nixfmt-rfc-style;
          };
          deadnix.enable = true;
          statix.enable = true;
          shfmt = {
            enable = true;
            indent_size = 2;
          };
        };
        settings.formatter.powershell = {
          command = powershell.format;
          includes = [
            "*.ps1"
            "*.psd1"
          ];
        };
      };

      pre-commit.settings.hooks.treefmt = {
        enable = true;
        package = config.treefmt.build.wrapper;
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.pre-commit.devShell ];
        packages = [
          pkgs.nixd
          pkgs.just
          pkgs.nixfmt-rfc-style
        ];
      };
    };
}
