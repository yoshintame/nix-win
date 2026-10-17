{
  description = "Declarative Windows configuration from NixOS-WSL: registry, services, firewall, files and typed tweaks";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      example = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.default
          ./tests/example.nix
        ];
      };
      render = example.config.windows.build.toplevel;
    in
    {
      nixosModules.default = ./module;

      checks = forAllSystems (
        pkgs:
        {
          eval = pkgs.runCommandLocal "nix-win-eval" { } ''
            echo ${lib.escapeShellArg (builtins.unsafeDiscardStringContext render.drvPath)} > $out
          '';
        }
        // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
          render = pkgs.runCommandLocal "nix-win-render" { } ''
            bash ${./tests/render.sh} ${render}
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
