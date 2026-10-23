{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  patterns = import ./patterns.nix;

  timeout = types.ints.between 1 2147483;
  value = types.nullOr (types.either types.ints.u32 (types.strMatching patterns.line));
  keys =
    root:
    mkOption {
      type = types.attrsOf (types.nullOr (types.attrsOf value));
      default = { };
      description = "Keys under ${root} by path. A value that is an integer is written as REG_DWORD, a string as REG_SZ, `null` deletes it; `{ }` creates an empty key, `null` instead of the values deletes the key with everything under it.";
    };
in
{
  options.windows = {
    enable = lib.mkEnableOption "nix-win";

    flake = mkOption {
      type = types.str;
      description = "Flake reference `<flake>#<host>` that `windows-rebuild` builds when `--flake` is not given.";
    };

    registry = {
      HKLM = keys "HKLM";
      HKCU = keys "the HKCU of every user in `windows.users`";
    };

    users = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options.profile = mkOption {
              type = types.strMatching patterns.plain;
              default = ''C:\Users\${name}'';
              description = "Profile directory with the user's `NTUSER.DAT`.";
            };
          }
        )
      );
      default = { };
      description = "Users whose HKCU receives `windows.registry.HKCU`: the caller's directly, others through `reg load` while they are signed out.";
    };

    services = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            startType = mkOption {
              type = types.nullOr (
                types.enum [
                  "auto"
                  "delayed-auto"
                  "demand"
                  "disabled"
                ]
              );
              default = null;
              description = "Start type set with `sc config`; `null` leaves it as is.";
            };
            state = mkOption {
              type = types.nullOr (
                types.enum [
                  "running"
                  "stopped"
                ]
              );
              default = null;
              description = "State ensured with `net start` / `net stop`; `null` leaves it as is.";
            };
          };
        }
      );
      default = { };
      description = "Services by name.";
    };

    firewall.rules = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              displayName = mkOption {
                type = types.strMatching patterns.displayName;
                default = name;
                description = "Display name; other rules with this display name are removed.";
              };
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Whether the rule is enabled.";
              };
              direction = mkOption {
                type = types.enum [
                  "Inbound"
                  "Outbound"
                ];
                default = "Inbound";
                description = "Traffic direction.";
              };
              action = mkOption {
                type = types.enum [
                  "Allow"
                  "Block"
                ];
                default = "Allow";
                description = "Action for matching traffic.";
              };
              protocol = mkOption {
                type = types.enum [
                  "TCP"
                  "UDP"
                  "ICMPv4"
                  "ICMPv6"
                  "Any"
                ];
                default = "TCP";
                description = "IP protocol.";
              };
              localPort = mkOption {
                type = types.nullOr (types.either types.port (types.strMatching patterns.port));
                default = null;
                description = "Local port, list or range of ports for TCP and UDP; `null` matches any port.";
              };
              remoteAddress = mkOption {
                type = types.listOf (types.strMatching patterns.address);
                default = [ ];
                description = "Remote addresses, subnets or ranges; empty matches any address.";
              };
              interfaceAlias = mkOption {
                type = types.nullOr (types.strMatching patterns.interfaceAlias);
                default = null;
                description = "Alias of the only interface the rule applies to; `null` applies it to every interface.";
              };
            };
          }
        )
      );
      default = { };
      description = "Firewall rules by their stable `Name`, created with `New-NetFirewallRule` or updated with `Set-NetFirewallRule`.";
    };

    capabilities = mkOption {
      type = types.listOf (types.strMatching patterns.capability);
      default = [ ];
      description = "Windows capabilities to install, such as `OpenSSH.Server~~~~0.0.1.0`.";
    };

    files = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            text = mkOption {
              type = types.lines;
              description = "Content of the file.";
            };
            grants = mkOption {
              type = types.listOf (types.strMatching patterns.grant);
              default = [ ];
              description = "`icacls` grants that replace the ACL of the file, with Administrators as owner; empty keeps the inherited ACL.";
            };
            validate = mkOption {
              type = types.nullOr (types.functionTo types.str);
              default = null;
              description = "Function from the quoted path of the new content to a cmd line that must succeed before the content replaces the file.";
            };
            onChange = mkOption {
              type = types.lines;
              default = "";
              description = "cmd lines run in order after the file changed; until all of them succeed, every switch runs them again.";
            };
          };
        }
      );
      default = { };
      description = "Files by absolute path, copied when their content differs.";
    };

    power = {
      timeouts = mkOption {
        type = types.attrsOf types.ints.unsigned;
        default = { };
        description = "`powercfg /change` settings in minutes, such as `standby-timeout-ac`.";
      };
      hibernate = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Whether hibernation is available; `null` leaves it as is.";
      };
    };

    scheduledTasks = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.enable = mkOption {
            type = types.bool;
            description = "Whether the task is enabled.";
          };
        }
      );
      default = { };
      description = "Scheduled tasks by full path; a task that does not exist is skipped.";
    };

    networkAdapters.powerManagement = mkOption {
      type = types.attrsOf (types.strMatching patterns.word);
      default = { };
      description = "`Set-NetAdapterPowerManagement` properties of physical Ethernet adapters, such as `WakeOnMagicPacket = \"Enabled\"`; set only where supported and different.";
    };

    winget = {
      packages = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              source = mkOption {
                type = types.enum [
                  "winget"
                  "msstore"
                ];
                default = "winget";
                description = "Source the package is installed from.";
              };
              name = mkOption {
                type = types.nullOr (types.strMatching patterns.plain);
                default = null;
                description = "Readable name for an opaque ID, such as an msstore one; not used by the install.";
              };
              location = mkOption {
                type = types.nullOr (types.strMatching patterns.location);
                default = null;
                description = "Absolute install directory passed as `--location`, for packages that refuse to install without one; only Administrators should be able to write to it, since the elevated installer puts its files there.";
              };
              installerType = mkOption {
                type = types.nullOr (types.enum (import ./installer-types.nix));
                default = null;
                description = "Installer type passed as `--installer-type`, for packages whose manifest offers several installers and winget picks one that cannot install machine-wide.";
              };
              timeout = mkOption {
                type = timeout;
                default = config.windows.winget.timeout;
                defaultText = lib.literalExpression "config.windows.winget.timeout";
                description = "Seconds the install may take.";
              };
            };
          }
        );
        default = { };
        description = "winget packages of the machine by package ID, installed machine-wide (`--scope machine`) by `windows-rebuild switch --winget` and verified by `windows-rebuild check --winget`.";
      };
      bundle = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = lib.literalExpression "./winget.bundle.json";
        description = "JSON object of packages in the form of `windows.winget.packages`, merged into it; the `winget` command keeps it up to date.";
      };
      bundleFile = mkOption {
        type = types.nullOr (types.strMatching patterns.absolutePath);
        default = null;
        example = "/home/alice/dotfiles/hosts/pc/winget.bundle.json";
        description = "Absolute path of `windows.winget.bundle` in the working tree of the configuration; set, it installs a `winget` command in the distribution that runs `winget.exe` and records `install` / `uninstall` in this file.";
      };
      timeout = mkOption {
        type = timeout;
        default = 900;
        description = "Seconds a package install may take before its process tree is stopped and the package is reported as failed.";
      };
    };

    build.toplevel = mkOption {
      type = types.package;
      readOnly = true;
      description = "Rendered scripts and files that `windows-rebuild` stages and runs.";
    };

    build.winget = mkOption {
      type = types.package;
      readOnly = true;
      description = "The `winget` wrapper that records installs in `windows.winget.bundleFile`.";
    };

    build.rebuild = mkOption {
      type = types.package;
      readOnly = true;
      description = "The `windows-rebuild` command.";
    };
  };
}
