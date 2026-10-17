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
| `windows.registry.{HKLM,HKCU}."<key path>".<value>` | `reg add` / `reg delete`; an integer is `REG_DWORD`, a string `REG_SZ`, `null` deletes the value or the whole key |
| `windows.users.<name>.profile` | HKCU of other users through `reg load` while they are signed out |
| `windows.services.<name>` | `sc config`, `net start` / `net stop` |
| `windows.firewall.rules.<Name>` | `New-NetFirewallRule`, replacing rules with the same `Name` or `DisplayName` |
| `windows.capabilities` | `Add-WindowsCapability` |
| `windows.files."<path>"` | copy when changed, `icacls` grants, `onChange` commands |
| `windows.power`, `windows.scheduledTasks`, `windows.networkAdapters.powerManagement` | `powercfg`, `schtasks`, `Set-NetAdapterPowerManagement` |

Tweaks and raw registry values merge into one tree: setting the same value differently in both fails evaluation, `lib.mkForce` overrides.

## How it runs

- The distribution needs `wsl.interop.register = true`; Windows tools are called by absolute path.
- `switch` runs `apply.cmd` straight from the store over `\\wsl.localhost`. From a normal terminal it elevates once through the built-in `sudo.exe` in inline mode (`windows.defaults.system.sudo = "inline"`); from an SSH session the token is already elevated and no prompt appears.
- The caller's HKCU is written directly; other users' hives are loaded, written and unloaded, and skipped while they are signed in.
- Verification reads every declared value back with `reg query` and compares it with the line Nix expects.
- Not covered: rollback, drift detection outside the registry, values with line breaks.
