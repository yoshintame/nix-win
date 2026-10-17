# nix-win

NixOS module that configures the Windows host of a NixOS-WSL distribution: options under `windows.*` render one cmd script into the Nix store, `windows-rebuild switch|check` runs it from the store over `\\wsl.localhost` with one elevation and verifies the registry with `reg query` read back from stdout. Consumed by dotfiles (`~/.dotfiles`, host `lasthaze-gaming`) as `inputs.nix-win`; host values live there, not here.

## Layout

- `module/options.nix` — the `windows.*` options with narrow types; `module/checks.nix` — name checks (case clashes, quotes, line breaks, HKCU without users), used both as NixOS assertions and as a guard on the render itself; `module/defaults/` — typed tweak catalog `windows.defaults.<group>.<tweak>`, one file per group.
- `module/render/` — options → `nix-win.cmd <apply|verify>` and `expected.tsv`: `registry.nix` (operations with apply, query and expected line), `commands.nix` (capabilities, firewall, services, files, power, tasks, adapters), `cmd.nix` (cmd, C runtime and PowerShell quoting).
- `module/rebuild/` — `windows-rebuild.sh` and `compare.awk`.
- `tests/` and `parts/checks.nix` — example configuration, render content test, configurations that must fail evaluation.
- `dev/` — inputs of the `dev` partition (nixpkgs, treefmt-nix, git-hooks), so consumers of the module only follow `flake-parts`.

## Invariants

- Registry values are applied per value with `reg add`; the HKCU set is rendered once under `%root%`, which is `HKCU` for the caller and `HKU\nix-win-<user>` for a loaded hive. Machine and every user are scopes of the same script.
- Every registry operation has a `reg query` and an expected outcome; anything that cannot be verified must fail evaluation, never be skipped. The elevated process writes no files: results go to stdout between `@@ <scope> <n>` markers, and only `FAILED ` / `skip ` lines may appear outside them.
- Generated scripts are UTF-8 with CRLF and start with `chcp 65001`; arguments go through `cmd.arg` (C runtime quoting, `%%`, carets outside cmd quotes).
- Behaviour on Windows is verified on a real host before release: escaping, exit codes and hive handling are not testable in the Nix sandbox.

## Gates

- `just check` = `nix flake check`: treefmt (nixfmt, deadnix, statix, shfmt), pre-commit, eval of the example and of the rejected configurations on every system, render build and content test on x86_64-linux.
- `just fmt` = `nix fmt`.
