{ lib, ... }:
let
  inherit (lib) mkOption types;

  value = types.nullOr (types.either types.ints.u32 types.str);
  keys = mkOption {
    type = types.attrsOf (types.nullOr (types.attrsOf value));
    default = { };
  };
in
{
  options.windows = {
    enable = lib.mkEnableOption "nix-win";

    flake = mkOption {
      type = types.str;
    };

    registry = {
      HKLM = keys;
      HKCU = keys;
    };

    users = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options.profile = mkOption {
              type = types.str;
              default = ''C:\Users\${name}'';
            };
          }
        )
      );
      default = { };
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
            };
            state = mkOption {
              type = types.nullOr (
                types.enum [
                  "running"
                  "stopped"
                ]
              );
              default = null;
            };
          };
        }
      );
      default = { };
    };

    firewall.rules = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              displayName = mkOption {
                type = types.str;
                default = name;
              };
              enable = mkOption {
                type = types.bool;
                default = true;
              };
              direction = mkOption {
                type = types.enum [
                  "Inbound"
                  "Outbound"
                ];
                default = "Inbound";
              };
              action = mkOption {
                type = types.enum [
                  "Allow"
                  "Block"
                ];
                default = "Allow";
              };
              protocol = mkOption {
                type = types.str;
                default = "TCP";
              };
              localPort = mkOption {
                type = types.nullOr (types.either types.port types.str);
                default = null;
              };
              remoteAddress = mkOption {
                type = types.listOf types.str;
                default = [ ];
              };
            };
          }
        )
      );
      default = { };
    };

    capabilities = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    files = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            text = mkOption {
              type = types.lines;
            };
            grants = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            onChange = mkOption {
              type = types.lines;
              default = "";
            };
          };
        }
      );
      default = { };
    };

    power = {
      timeouts = mkOption {
        type = types.attrsOf types.ints.unsigned;
        default = { };
      };
      hibernate = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
    };

    scheduledTasks = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.enable = mkOption {
            type = types.bool;
          };
        }
      );
      default = { };
    };

    networkAdapters.powerManagement = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };

    build.toplevel = mkOption {
      type = types.package;
      readOnly = true;
    };

    build.rebuild = mkOption {
      type = types.package;
      readOnly = true;
    };
  };
}
