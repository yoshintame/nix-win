{ lib }:
let
  inherit (lib)
    concatMapStrings
    concatStringsSep
    imap0
    replaceStrings
    ;

  specials = lib.stringToCharacters "^&|<>()";
  psQuotes = [
    "'"
    "‘"
    "’"
    "‚"
    "‛"
  ];
  caret = replaceStrings specials (map (c: "^" + c) specials);
  doubleTrailingBackslashes =
    piece: piece + lib.elemAt (builtins.match "(.*[^\\\\])?(\\\\*)" piece) 1;
  quotePiece =
    i: piece:
    replaceStrings [ "%" ] [ "%%" ] (
      (if lib.mod i 2 == 0 then lib.id else caret) (doubleTrailingBackslashes piece)
    );
in
rec {
  crlf = concatMapStrings (line: line + "\r\n");
  percent = replaceStrings [ "%" ] [ "%%" ];
  quote = s: lib.throwIf (lib.hasInfix "\"" s) "nix-win: unexpected quote in ${s}" "\"${percent s}\"";
  arg =
    s:
    let
      pieces = lib.splitString "\"" s;
      closing = if lib.mod (builtins.length pieces) 2 == 0 then "^\"" else "\"";
    in
    "\"${concatStringsSep "\\\"" (imap0 quotePiece pieces)}${closing}";
  psString = s: "'${replaceStrings psQuotes (map (q: q + q) psQuotes) s}'";
  escapeEcho = s: percent (caret s);
  pad = i: lib.fixedWidthString 4 "0" (toString i);
  fail = label: "(echo FAILED ${escapeEcho label}& set failed=1)";
}
