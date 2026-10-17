{
  description = "Declarative Windows configuration from NixOS-WSL: registry, services, firewall, files and typed tweaks";

  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ flake-parts.flakeModules.partitions ];

      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      flake.nixosModules.default = ./module;

      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
      };

      partitions.dev = {
        extraInputsFlake = ./dev;
        module =
          { inputs, ... }:
          {
            imports = [
              inputs.treefmt-nix.flakeModule
              inputs.git-hooks.flakeModule
              ./parts/dev.nix
              ./parts/checks.nix
            ];
          };
      };
    };
}
