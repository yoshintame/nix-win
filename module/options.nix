{ lib, ... }:
let
  inherit (lib) mkOption types;

  matching = regex: types.strMatching regex;
  line = matching "[^\r\n\t]*";
  safe = matching "[^\r\n\t\"]+";
  word = matching "[A-Za-z0-9._~-]+";

  option =
    type: default:
    mkOption {
      inherit type default;
    };

  value = types.nullOr (types.either types.ints.u32 line);
  keys = option (types.attrsOf (types.nullOr (types.attrsOf value))) { };
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

    users = option (types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options.profile = option safe ''C:\Users\${name}'';
        }
      )
    )) { };

    services = option (types.attrsOf (
      types.submodule {
        options = {
          startType = option (types.nullOr (
            types.enum [
              "auto"
              "delayed-auto"
              "demand"
              "disabled"
            ]
          )) null;
          state = option (types.nullOr (
            types.enum [
              "running"
              "stopped"
            ]
          )) null;
        };
      }
    )) { };

    firewall.rules = option (types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            displayName = option (matching "[^\r\n\t\"'‘’‚‛]+") name;
            enable = option types.bool true;
            direction = option (types.enum [
              "Inbound"
              "Outbound"
            ]) "Inbound";
            action = option (types.enum [
              "Allow"
              "Block"
            ]) "Allow";
            protocol = option (types.enum [
              "TCP"
              "UDP"
              "ICMPv4"
              "ICMPv6"
              "Any"
            ]) "TCP";
            localPort = option (types.nullOr (types.either types.port (matching "[0-9,-]+"))) null;
            remoteAddress = option (types.listOf (matching "[0-9A-Fa-f:./-]+")) [ ];
            interfaceAlias = option (types.nullOr (matching "[A-Za-z0-9 ._()-]+")) null;
          };
        }
      )
    )) { };

    capabilities = option (types.listOf word) [ ];

    files = option (types.attrsOf (
      types.submodule {
        options = {
          text = mkOption {
            type = types.lines;
          };
          grants = option (types.listOf (matching "\\*?[A-Za-z0-9-]+:\\(?[A-Z,]+\\)?")) [ ];
          onChange = option types.lines "";
        };
      }
    )) { };

    power = {
      timeouts = option (types.attrsOf types.ints.unsigned) { };
      hibernate = option (types.nullOr types.bool) null;
    };

    scheduledTasks = option (types.attrsOf (
      types.submodule {
        options.enable = mkOption {
          type = types.bool;
        };
      }
    )) { };

    networkAdapters.powerManagement = option (types.attrsOf (matching "[A-Za-z]+")) { };

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
