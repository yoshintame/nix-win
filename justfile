default:
    @just --list

check:
    nix flake check
    nix build --no-link .#checks.x86_64-linux.render .#checks.x86_64-linux.compare

fmt:
    nix fmt

update:
    nix flake update
