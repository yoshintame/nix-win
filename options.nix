{ lib, ... }:
let
  inherit (lib) mkOption types;

  tree = mkOption {
    type = types.anything;
    default = { };
  };
in
{
  options.windows = {
    enable = lib.mkEnableOption "nix-windows";

    flake = mkOption {
      type = types.str;
    };

    registry = mkOption {
      type = types.submodule {
        options = {
          HKLM = tree;
          HKCU = tree;
        };
      };
      default = { };
    };

    deletedKeys = mkOption {
      type = types.listOf (types.strMatching ''(HKLM|HKCU)\\.+'');
      default = [ ];
    };

    users = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              profile = mkOption {
                type = types.str;
                default = ''C:\Users\${name}'';
              };
              registry = tree;
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
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
            };
            direction = mkOption {
              type = types.enum [
                "in"
                "out"
              ];
              default = "in";
            };
            action = mkOption {
              type = types.enum [
                "allow"
                "block"
              ];
              default = "allow";
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
            program = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };
        }
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
              type = types.nullOr types.lines;
              default = null;
            };
            source = mkOption {
              type = types.nullOr types.path;
              default = null;
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
  };
}
