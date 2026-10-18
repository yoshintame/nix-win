# nix-win

Declarative configuration of a Windows host from the NixOS-WSL distribution running on it, in the spirit of nix-darwin. Packages stay with `winget configure`; nix-win owns everything else: registry (HKLM and the HKCU of every listed user), services, firewall rules, Windows capabilities, files with ACLs, power settings, scheduled tasks and network adapter power management.

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
windows-rebuild switch   # apply, then verify every registry value
windows-rebuild check    # verify only; non-zero exit on drift
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

Registry paths and value names are case-insensitive on Windows, so two spellings that differ only in the case of ASCII letters fail evaluation (`lib.toLower` folds no other letters). Tweaks and raw values merge into one tree: setting the same value differently fails evaluation, `lib.mkForce` overrides. HKCU values need at least one entry in `windows.users`; `HKCU\Software\Classes` is rejected because a loaded `NTUSER.DAT` does not contain it.

## How it runs

- The distribution needs `wsl.interop.register = true`; Windows tools are called by absolute path and scripts run with a system-only `PATH` and `PSModulePath`.
- `switch` elevates once: through the built-in `sudo.exe` from a normal terminal (it must run inline or with input disabled, `windows.defaults.system.sudo`), directly from an SSH session or SYSTEM. The elevated `stage.cmd` copies the rendered files from the store (over `\\wsl.localhost`) into `%ProgramFiles%\nix-win`, where other users cannot create anything in advance and only Administrators and SYSTEM have access (its ACL is reapplied on every run; a link at that path is removed as a link, anything else untrusted is renamed aside), and runs `nix-win.cmd apply` from there in one `cmd.exe /d` process; capabilities, firewall rules and adapters go through one PowerShell script. `check` without elevation runs `nix-win.cmd verify` from a copy in `%TEMP%`.
- Every applied value, deletion and created key is read back with `reg query`; results go to stdout between `@@ <scope> <n>` markers and `compare.awk` matches them against the lines Nix expects. The machine scope always prints its marker first, so `switch` and `check` fail on drift, on missing values and when no results came back from Windows.
- Other users' hives are loaded, written, verified and unloaded; a signed-in user (including a disconnected session) is skipped and reported as not checked.

## Threat model

The script that runs elevated comes from the NixOS-WSL distribution. Anyone who can run code as the Windows user can become root in that distribution (`wsl -u root`) and change what the next `switch` executes, so root in the distribution is effectively administrator on Windows. nix-win removes the cheaper paths — the elevated run executes only from a directory users cannot write, writes no results to files, and ignores `AutoRun`, user PowerShell modules and the user `PATH` — but it does not create a boundary between the Windows user and the elevated run: variables such as `%SystemRoot%` and `%ProgramFiles%` still come from that user's environment. Files in `windows.files` are written through links in their target paths, so they belong in directories only Administrators can write.

Not covered: rollback, drift detection outside the registry, values with line breaks, `REG_EXPAND_SZ` / `REG_MULTI_SZ` / binary values, the default value of a key.
