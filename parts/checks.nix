{ inputs, self, ... }:
let
  build =
    extra:
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.default
        ../tests/example.nix
        extra
      ];
    }).config.windows.build.toplevel;
  render = build { };

  rejected = {
    case-clash.windows.registry.HKLM."software\\nixwin\\example".Other = 1;
    hkcu-without-users = {
      windows.users = inputs.nixpkgs.lib.mkForce { };
    };
    user-classes.windows.registry.HKCU."Software\\Classes\\CLSID".X = 1;
    line-break.windows.registry.HKLM."SOFTWARE\\NixWin\\Example"."a\nb" = 1;
    trailing-backslash.windows.registry.HKLM."SOFTWARE\\NixWin\\".X = 1;
    double-backslash.windows.registry.HKLM."SOFTWARE\\\\NixWin".X = 1;
    deleted-parent.windows.registry.HKLM."SOFTWARE\\NixWin\\removed\\Child".X = 1;
    firewall-display-name.windows.firewall.rules.Other-In-TCP.displayName = "example (tcp)";
    firewall-name-case.windows.firewall.rules.example-in-tcp = { };
    firewall-port-protocol.windows.firewall.rules.Ping-In = {
      protocol = "ICMPv4";
      localPort = 8;
    };
  };
  accepted = inputs.nixpkgs.lib.filterAttrs (
    _: config: (builtins.tryEval (builtins.seq (build config).drvPath true)).success
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
          lib.throwIf (accepted != { })
            "nix-win: configurations expected to fail evaluation passed: ${lib.concatStringsSep ", " (builtins.attrNames accepted)}"
            (pkgs.runCommandLocal "nix-win-rejects-invalid" { } "touch $out");
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        render = pkgs.runCommandLocal "nix-win-render" { } ''
          bash ${../tests/render.sh} ${render}
          touch $out
        '';
        compare = pkgs.runCommandLocal "nix-win-compare" { } ''
          bash ${../tests/compare.sh} ${../module/rebuild/compare.awk} ${render}/expected.tsv
          touch $out
        '';
      };
    };
}
