{ lib }:
let
  inherit (lib) concatMapStrings replaceStrings;

  echoSpecials = lib.stringToCharacters "^&|<>()";
in
rec {
  crlf = concatMapStrings (line: line + "\r\n");

  quote = s: "\"${replaceStrings [ "%" ] [ "%%" ] s}\"";

  escapeEcho = replaceStrings (echoSpecials ++ [ "%" ]) (map (c: "^" + c) echoSpecials ++ [ "%%" ]);

  winPath = replaceStrings [ "/" ] [ "\\" ];

  winDir = p: lib.concatStringsSep "\\" (lib.init (lib.splitString "\\" p));

  pad = i: lib.fixedWidthString 4 "0" (toString i);

  fail = label: "(echo FAILED ${escapeEcho label}& set failed=1)";

  file = path: lines: {
    inherit path;
    encoding = "utf8";
    text = crlf lines;
  };

  script =
    path: body:
    file path (
      [
        "@echo off"
        "setlocal"
        "chcp 65001 >nul"
        "set failed=0"
      ]
      ++ body
      ++ [ "exit /b %failed%" ]
    );
}
