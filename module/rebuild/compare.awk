function trim(s) {
  gsub(/^ +| +$/, "", s)
  return s
}
FILENAME == ARGV[1] {
  if ($0 ~ /^@@ /) {
    split($0, marker, " ")
    current = marker[2] SUBSEP marker[3]
    seen[marker[2]] = 1
    markers++
    output[current] = ""
  } else if ($0 ~ /^(FAILED|skip) /) {
    print
  } else if (current != "") {
    output[current] = output[current] "\n" $0
  }
  next
}
{
  rows++
  if (!($1 in seen)) {
    skipped[$1] = 1
    next
  }
  found = 0
  present = 0
  actual = ""
  n = split(output[$1 SUBSEP $2], lines, "\n")
  for (i = 1; i <= n; i++) {
    if (lines[i] == $5) found = 1
    if (lines[i] ~ /[^ ]/) present = 1
    if (lines[i] ~ /^    /) actual = lines[i]
  }
  if ($3 == "value" && found) ok++
  else if ($3 == "value" && present) {
    drift++
    print "drift    " $4 ": " trim(actual) ", expected " trim($5)
  } else if ($3 == "value" || ($3 == "present" && !present)) {
    missing++
    print "missing  " $4
  } else if ($3 == "absent" && present) {
    drift++
    print "present  " $4
  } else ok++
}
END {
  if (rows && !markers) {
    print "nix-win: no results from Windows"
    exit 1
  }
  printf "nix-win: %d ok, %d drift, %d missing", ok, drift, missing
  for (s in skipped) printf ", %s not checked", s
  print ""
  exit (drift + missing > 0 || ("machine" in skipped))
}
