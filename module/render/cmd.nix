{ lib }:
let
  inherit (lib)
    concatMapStrings
    elem
    foldl'
    replaceStrings
    stringToCharacters
    ;

  specials = stringToCharacters "^&|<>()";
  backslashes = n: lib.strings.replicate n "\\";

  crtQuote =
    s:
    let
      r =
        foldl'
          (
            acc: c:
            if c == "\\" then
              acc // { bs = acc.bs + 1; }
            else
              {
                out = acc.out + (if c == "\"" then backslashes (2 * acc.bs + 1) else backslashes acc.bs) + c;
                bs = 0;
              }
          )
          {
            out = "";
            bs = 0;
          }
          (stringToCharacters s);
    in
    "\"${r.out}${backslashes (2 * r.bs)}\"";

  cmdSafe =
    s:
    (foldl'
      (
        acc: c:
        if c == "\"" then
          {
            out = acc.out + c;
            quoted = !acc.quoted;
          }
        else
          acc
          // {
            out =
              acc.out
              + (
                if c == "%" then
                  "%%"
                else if !acc.quoted && elem c specials then
                  "^" + c
                else
                  c
              );
          }
      )
      {
        out = "";
        quoted = false;
      }
      (stringToCharacters s)
    ).out;
in
rec {
  crlf = concatMapStrings (line: line + "\r\n");
  quote = s: "\"${replaceStrings [ "%" ] [ "%%" ] s}\"";
  arg = s: cmdSafe (crtQuote s);
  psString = s: "'${replaceStrings [ "'" "%" ] [ "''" "%%" ] s}'";
  escapeEcho = replaceStrings (specials ++ [ "%" ]) (map (c: "^" + c) specials ++ [ "%%" ]);
  pad = i: lib.fixedWidthString 4 "0" (toString i);
  fail = label: "(echo FAILED ${escapeEcho label}& set failed=1)";
  powershell = command: label: "powershell -NoProfile -Command \"${command}\" || ${fail label}";
}
