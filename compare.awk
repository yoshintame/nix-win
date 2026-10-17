function trim(s) { gsub(/^ +| +$/, "", s); return s }
$1 ~ /^user-/ && $1 != "user-" caller { next }
$1 == "hive-" caller { next }
{
  file = dir "/out/" $1 "/" $2 ".txt"
  status = (getline line < file)
  if (status < 0) { skipped[$1] = 1; next }
  found = 0; present = 0; actual = ""
  while (status > 0) {
    sub(/\r$/, "", line)
    if (line == $5) found = 1
    if (line ~ /[^ ]/) present = 1
    if (line ~ /^    /) actual = line
    status = (getline line < file)
  }
  close(file)
  if ($3 == "value" && found) ok++
  else if ($3 == "value" && present) { drift++; print "drift    " $4 ": " trim(actual) ", expected " trim($5) }
  else if ($3 == "value") { missing++; print "missing  " $4 }
  else if (present) { drift++; print "present  " $4 }
  else ok++
}
END {
  printf "nix-windows: %d ok, %d drift, %d missing", ok, drift, missing
  for (s in skipped) printf ", %s not checked", s
  print ""
  exit (drift + missing > 0)
}
