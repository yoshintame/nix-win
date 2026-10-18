{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  system =
    extra:
    lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.default
        ../tests/example.nix
        extra
      ];
    };
  render = (system { }).config.windows.build.toplevel;

  rejected = {
    case-clash = {
      config.windows.registry.HKLM."software\\nixwin\\example".Other = 1;
      message = "HKLM key paths differ only in case";
    };
    hkcu-without-users = {
      config.windows.users = lib.mkForce { };
      message = "windows.users is empty";
    };
    user-classes = {
      config.windows.registry.HKCU."Software\\Classes\\CLSID".X = 1;
      message = "lives in UsrClass.dat";
    };
    line-break = {
      config.windows.registry.HKLM."SOFTWARE\\NixWin\\Example"."a\nb" = 1;
      message = "value name in HKLM\\SOFTWARE\\NixWin\\Example";
    };
    trailing-backslash = {
      config.windows.registry.HKLM."SOFTWARE\\NixWin\\".X = 1;
      message = "HKLM key path 'SOFTWARE\\NixWin\\' must match";
    };
    double-backslash = {
      config.windows.registry.HKLM."SOFTWARE\\\\NixWin".X = 1;
      message = "HKLM key path 'SOFTWARE\\\\NixWin' must match";
    };
    deleted-parent = {
      config.windows.registry.HKLM."SOFTWARE\\NixWin\\removed\\Child".X = 1;
      message = "is deleted, but keys under it are set";
    };
    firewall-display-name = {
      config.windows.firewall.rules.Other-In-TCP.displayName = "Пример — EXAMPLE (tcp)";
      message = "firewall rules share a display name";
    };
    firewall-name-case = {
      config.windows.firewall.rules.example-in-tcp = { };
      message = "firewall rule names differ only in case";
    };
    firewall-port-protocol = {
      config.windows.firewall.rules.Ping-In = {
        protocol = "ICMPv4";
        localPort = 8;
      };
      message = "needs protocol TCP or UDP";
    };
    user-case = {
      config.windows.users.ALICE = { };
      message = "user names differ only in case";
    };
    file-path-case = {
      config.windows.files."C:\\PROGRAMDATA\\NixWin\\example.conf".text = "";
      message = "file paths differ only in case";
    };
  };
  failures =
    config: map (a: a.message) (lib.filter (a: !a.assertion) (system config).config.assertions);
  missed = lib.filterAttrs (
    _: case: !lib.any (lib.hasInfix case.message) (failures case.config)
  ) rejected;
in
{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks = {
        eval = pkgs.runCommandLocal "nix-win-eval" { } ''
          printf '%s\n' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext render.drvPath)} > $out
        '';
        rejects-invalid =
          lib.throwIf (missed != { })
            "nix-win: configurations not rejected for the expected reason: ${lib.concatStringsSep ", " (builtins.attrNames missed)}"
            (pkgs.runCommandLocal "nix-win-rejects-invalid" { } "touch $out");
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        render = pkgs.runCommandLocal "nix-win-render" { } ''
          bash ${../tests/render.sh} ${render}
          bash ${../tests/compare.sh} ${../module/rebuild/compare.awk} ${render}/expected.tsv
          touch $out
        '';
      };
    };
}
