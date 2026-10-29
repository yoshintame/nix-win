# nix-win

Declarative configuration of a Windows host from the NixOS-WSL distribution running on it, in the spirit of nix-darwin. nix-win owns machine-wide winget packages, the registry (HKLM and the HKCU of every listed user), services, firewall rules, Windows capabilities, files with ACLs, power settings, scheduled tasks and network adapter power management.

NixOS modules declare the state, nix-win renders it into native Windows scripts in the Nix store, and `windows-rebuild` applies them with a single elevation and verifies the result.

## Usage

```nix
{
  inputs.nix-win.url = "github:yoshintame/nix-win";

  outputs = { nixpkgs, nixos-wsl, nix-win, ... }: {
    nixosConfigurations.my-pc = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nix-win.nixosModules.default
        {
          wsl.enable = true;
          wsl.interop.register = true;

          windows = {
            enable = true;
            flake = "/home/me/config#my-pc";
            users.me = { };

            defaults = {
              explorer = { showFileExtensions = true; launchTo = "thisPC"; };
              ai = { copilot = false; recall = false; };
              privacy.telemetry = "required";
              system.sudo = "inline";
            };

            registry.HKCU."Software\\Example".Answer = 42;
          };
        }
      ];
    };
  };
}
```

```sh
windows-rebuild switch            # apply, then verify every registry value
windows-rebuild check             # verify only; non-zero exit on drift
windows-rebuild switch --winget   # install the winget packages first, then apply and verify them too
windows-rebuild check --winget    # verify, including that every winget package is installed
```

## Options

| Option | Applied with |
|---|---|
| `windows.defaults.<group>.<tweak>` | typed tweaks (`explorer`, `start`, `search`, `suggestions`, `privacy`, `ai`, `gaming`, `system`); `null` leaves Windows untouched |
| `windows.registry.{HKLM,HKCU}."<key path>".<value>` | `reg add` / `reg delete`; an integer is `REG_DWORD`, a string `REG_SZ`, `null` deletes the value or the whole key, `{ }` creates an empty key |
| `windows.users.<name>.profile` | HKCU of every listed user: the caller's directly, others through `reg load` while they are signed out |
| `windows.services.<name>` | `sc config`, `net start` / `net stop` |
| `windows.firewall.rules.<Name>` | `New-NetFirewallRule` or `Set-NetFirewallRule` by the stable `Name`, optionally bound to an interface; a port, address or interface left unset is reset to `Any`, other rules with the same `DisplayName` are removed |
| `windows.capabilities` | `Get-WindowsCapability` / `Add-WindowsCapability` |
| `windows.files."<path>"` | copy when changed and accepted by the optional `validate` command, ACL reset to the given grants with Administrators as owner, `onChange` commands right after the copy and again on every `switch` until they all succeed |
| `windows.power`, `windows.scheduledTasks`, `windows.networkAdapters.powerManagement` | `powercfg`, `schtasks`, `Set-NetAdapterPowerManagement` only where a supported property drifts |
| `windows.winget.packages."<id>"` | only with `--winget`: `winget install --scope machine --no-upgrade` one package at a time with an optional `source`, absolute `location` (a directory only Administrators can write to), `installerType` (for manifests whose default installer cannot install machine-wide, such as an MSIX next to an MSI) and `timeout`; verified with `winget list --id --exact --scope machine`, one call per package, so `check --winget` takes a few seconds per dozen packages. Packages without a machine-wide installer belong to per-user configuration, not here |
| `windows.winget.bundle`, `windows.winget.bundleFile` | `bundle` is a JSON object of packages merged into `windows.winget.packages`; `bundleFile` is the same file's path in the working tree and adds a `winget` command to the distribution. It runs `winget.exe` and, for `install` / `uninstall` of exactly one package ID, checks with `winget list --id --exact` whether the package is now installed machine-wide or gone and updates the bundle under a lock; fuzzy queries, manifests, other sources, other scopes and packages declared in Nix modules are left out with a note. It reads no winget output text, so a localized Windows works |

Registry paths and value names are case-insensitive on Windows, so two spellings that differ only in the case of ASCII letters fail evaluation (`lib.toLower` folds no other letters). Tweaks and raw values merge into one tree: setting the same value differently fails evaluation, `lib.mkForce` overrides. HKCU values need at least one entry in `windows.users`; `HKCU\Software\Classes` is rejected because a loaded `NTUSER.DAT` does not contain it.

## How it runs

- The distribution needs `wsl.interop.register = true`; Windows tools are called by absolute path and scripts run with a system-only `PATH` and `PSModulePath`.
- `switch` elevates once: through the built-in `sudo.exe` from a normal terminal (it must run inline or with input disabled, `windows.defaults.system.sudo`), directly from an SSH session or SYSTEM. The elevated `stage.cmd` copies the rendered files from the store (over `\\wsl.localhost`) into `%ProgramFiles%\nix-win`, where other users cannot create anything in advance and only Administrators and SYSTEM have access (its ACL is reapplied on every run; a link at that path is removed as a link, anything else untrusted is renamed aside), and runs `nix-win.cmd apply` from there in one `cmd.exe /d` process; capabilities, firewall rules and adapters go through one PowerShell script. `check` without elevation runs `nix-win.cmd verify` from a copy in `%TEMP%`.
- Every applied value, deletion and created key is read back with `reg query`; results go to stdout between `@@ <scope> <n>` markers and `compare.awk` matches them against the lines Nix expects. The machine scope always prints its marker first, so `switch` and `check` fail on drift, on missing values and when no results came back from Windows.
- Other users' hives are loaded, written, verified and unloaded; a signed-in user (including a disconnected session) is skipped and reported as not checked.
- winget packages are touched only with `--winget`, before everything else, so a package that a later step depends on (a network adapter a firewall rule is bound to) is already there. `winget.exe` is the caller's one Store-signed App Installer registration under the `PackageRoot` from HKLM, its Authenticode signature checked, not the user-writable alias; `--winget` is not supported under SYSTEM, which has no registration. The elevated winget downloads installers into `%ProgramFiles%\nix-win\winget\tmp` (`TMP` and `TEMP` point there) instead of the user's `%TEMP%`; winget moves a portable package's files out of there with that directory's administrators-only ACL, so after every successful install the package's folder under `%ProgramFiles%\WinGet\Packages` is reset to inherit its parent's ACL, which lets standard users run it. It refuses to run when the user's winget settings set `portablePackageMachineRoot` or `defaultInstallRoot` or use `\u` escapes; the settings files stay open for reading only while packages install, so they cannot change mid-run, but this is a best-effort guard rather than a boundary (see the threat model). Packages install one at a time: concurrent winget processes fail on its package database. An install that outlives its `timeout` (`windows.winget.timeout`, 900 s by default) has its process tree stopped; if Windows Installer is still busy after another `timeout`, the remaining packages are skipped. "Already installed" (also reported by the installer itself) and "a reboot finishes the install" count as success, every other exit code is a `FAILED` line. Progress goes to stderr, winget output to `%ProgramFiles%\nix-win\winget\<id>.log` and `.log.err`. Without `--winget` the packages are reported as not checked.

## Threat model

The script that runs elevated comes from the NixOS-WSL distribution. Anyone who can run code as the Windows user can become root in that distribution (`wsl -u root`) and change what the next `switch` executes, so root in the distribution is effectively administrator on Windows. nix-win removes the cheaper paths — the elevated run executes only from a directory users cannot write, writes no results to files, and ignores `AutoRun`, user PowerShell modules and the user `PATH` — but it does not create a boundary between the Windows user and the elevated run: variables such as `%SystemRoot%` and `%ProgramFiles%` still come from that user's environment. Files in `windows.files` are written through links in their target paths, so they belong in directories only Administrators can write.

Not covered: rollback, drift detection outside the registry, values with line breaks, `REG_EXPAND_SZ` / `REG_MULTI_SZ` / binary values, the default value of a key.
