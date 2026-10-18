default:
    @just --list

check:
    nix flake check
    nix build --no-link .#checks.x86_64-linux.render

fmt:
    nix fmt

update:
    nix flake update
