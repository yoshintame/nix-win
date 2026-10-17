{ inputs, self, ... }:
let
  example = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.default
      ../tests/example.nix
    ];
  };
  render = example.config.windows.build.toplevel;
in
{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks = {
        eval = pkgs.runCommandLocal "nix-win-eval" { } ''
          printf '%s\n' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext render.drvPath)} > $out
        '';
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        render = pkgs.runCommandLocal "nix-win-render" { } ''
          bash ${../tests/render.sh} ${render}
          touch $out
        '';
      };
    };
}
