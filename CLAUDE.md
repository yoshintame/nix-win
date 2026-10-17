# nix-win

NixOS module that configures the Windows host of a NixOS-WSL distribution: options under `windows.*` render native cmd scripts into the Nix store, `windows-rebuild switch|check` runs them from the store over `\\wsl.localhost` with one elevation and verifies the registry with `reg query`. Consumed by dotfiles (`~/.dotfiles`, host `lasthaze-gaming`) as `inputs.nix-win`; host values live there, not here.

## Layout

- `module/options.nix` — the `windows.*` options; `module/defaults/` — typed tweak catalog `windows.defaults.<group>.<tweak>`, each tweak declares its type, description and the registry keys, services or tasks it expands to.
- `module/render/` — options → `apply.cmd`, `users.cmd`, `verify.cmd`, `expected.tsv`: `registry.nix` (reg add/delete, queries, expected lines), `commands.nix` (capabilities, firewall, services, files, power, tasks, adapters), `cmd.nix` (cmd and C runtime quoting).
- `module/rebuild/` — `windows-rebuild.sh` and `compare.awk`.
- `tests/` — example configuration and the render content test.

## Invariants

- Registry values are applied per value with `reg add`; the HKCU set is rendered once under `%root%`, which is `HKCU` for the caller and `HKU\nix-win-<user>` for a loaded hive.
- Every applied value has an expected `reg query` line; anything that cannot be verified must fail evaluation, never be skipped.
- Generated scripts are UTF-8 with CRLF and start with `chcp 65001`; arguments go through `cmd.arg` (C runtime quoting, `%%`, carets outside cmd quotes).
- Behaviour on Windows is verified on a real host before release: escaping, exit codes and hive handling are not testable in the Nix sandbox.

## Gates

- `just check` = `nix flake check`: treefmt (nixfmt, deadnix, statix, shfmt), pre-commit, eval of the example on every system, render build and content test on x86_64-linux.
- `just fmt` = `nix fmt`.
