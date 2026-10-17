function trim(s) { gsub(/^ +| +$/, "", s); return s }
function check(scope, label,   file, status, line, found, present, actual) {
  file = dir "/" scope "/" $2 ".txt"
  status = (getline line < file)
  if (status < 0) { skipped[scope] = 1; return }
  while (status > 0) {
    sub(/\r$/, "", line)
    if (line == $5) found = 1
    if (line ~ /[^ ]/) present = 1
    if (line ~ /^    /) actual = line
    status = (getline line < file)
  }
  close(file)
  if ($3 == "value" && found) ok++
  else if ($3 == "value" && present) { drift++; print "drift    " label ": " trim(actual) ", expected " trim($5) }
  else if ($3 == "value") { missing++; print "missing  " label }
  else if (present) { drift++; print "present  " label }
  else ok++
}
BEGIN { n = split(users, names, " ") }
$1 == "machine" { check("machine", $4) }
$1 == "user" { for (i = 1; i <= n; i++) check("user-" names[i], names[i] ": " $4) }
END {
  printf "nix-windows: %d ok, %d drift, %d missing", ok, drift, missing
  for (s in skipped) printf ", %s not checked", s
  print ""
  exit (drift + missing > 0)
}
