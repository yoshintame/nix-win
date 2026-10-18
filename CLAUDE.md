# nix-win

NixOS module that configures the Windows host of a NixOS-WSL distribution: options under `windows.*` render one cmd script (plus one PowerShell script) into the Nix store; `windows-rebuild switch` elevates once, stages the files into an admin-only `%ProgramFiles%\nix-win` and runs them there, then verifies the registry with `reg query` read back from stdout. Consumed by dotfiles (`~/.dotfiles`, host `lasthaze-gaming`) as `inputs.nix-win`; host values live there, not here.

## Layout

- `module/options.nix` — the `windows.*` options with narrow types; `module/checks.nix` — name checks (malformed key paths, case clashes, quotes, line breaks, deleted keys with configured subkeys, HKCU without users, shared firewall display names), used both as NixOS assertions and as a guard on the render itself; `module/patterns.nix` — every input regex in one place, for option types and name checks; `module/defaults/` — typed tweak catalog `windows.defaults.<group>.<tweak>`, one file per group.
- `module/render/` — options → `nix-win.cmd <apply|verify>` and `expected.tsv`: `registry.nix` (operations with apply, query and expected line), `commands.nix` (capabilities, firewall, services, files, power, tasks, adapters), `cmd.nix` (cmd, C runtime and PowerShell quoting), `stage.ps1` (elevated staging).
- `module/rebuild/` — `windows-rebuild.sh` and `compare.awk`.
- `tests/` and `parts/checks.nix` — example configuration, render content test, `compare.awk` test, configurations that must fail evaluation.
- `dev/` — inputs of the `dev` partition (nixpkgs, treefmt-nix, git-hooks), so consumers of the module only follow `flake-parts`.

## Invariants

- Registry values are applied per value with `reg add`; the HKCU set is rendered once under `%root%`, which is `HKCU` for the caller and `HKU\nix-win-<user>` for a loaded hive. Machine and every user are scopes of the same script.
- Every registry operation has a `reg query` and an expected outcome; anything that cannot be verified must fail evaluation, never be skipped. Anything elevated runs from `%ProgramFiles%\nix-win\current`, created by `stage.ps1` with an Administrators-owned protected ACL reapplied on every run — never from `%TEMP%`, `%ProgramData%` (users can pre-create entries there) or straight from `\\wsl.localhost` (slow: cmd reads batch files line by line). Results go to stdout between `@@ <scope> <n>` markers, `@@ machine 0000` first, and only `FAILED ` / `skip ` lines may appear outside them; `expected.tsv` rows are `scope`, `index`, kind (`value` / `present` / `absent`), label and the expected `reg query` line, tab-separated.
- Pipelines that read Windows tools under `pipefail` (`windows-rebuild.sh`) use `grep … >/dev/null`, never `grep -q` or `head`: an early exit sends SIGPIPE to the writer and fails the pipeline.
- PowerShell scripts set `$global:ErrorActionPreference = 'Stop'`: CDXML cmdlets (NetSecurity, NetAdapter) read the global preference, not the script scope.
- Generated scripts are UTF-8 with CRLF and start with `chcp 65001`; arguments go through `cmd.arg` (C runtime quoting, `%%`, carets outside cmd quotes).
- Behaviour on Windows is verified on a real host before release: escaping, exit codes and hive handling are not testable in the Nix sandbox.

## Gates

- `just check` = `nix flake check`: treefmt (nixfmt, deadnix, statix, shfmt), pre-commit, eval of the example and of the rejected configurations on every system; then the x86_64-linux render build, content test and `compare.awk` test, built explicitly because `nix flake check` on macOS builds only checks of the current system.
- `just fmt` = `nix fmt`.
