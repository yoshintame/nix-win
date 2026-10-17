{
  description = "Declarative Windows configuration from NixOS-WSL: registry, services, firewall, files and typed tweaks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      treefmt-nix,
      git-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        treefmt-nix.flakeModule
        git-hooks.flakeModule
        ./parts/dev.nix
        ./parts/checks.nix
      ];

      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      flake.nixosModules.default = ./module;
    };
}
