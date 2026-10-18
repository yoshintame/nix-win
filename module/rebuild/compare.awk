function trim(s) {
  gsub(/^ +| +$/, "", s)
  return s
}
FILENAME == ARGV[1] {
  if ($0 ~ /^@@ /) {
    split($0, marker, " ")
    current = marker[2] SUBSEP marker[3]
    seen[marker[2]] = 1
    output[current] = ""
  } else if ($0 ~ /^(FAILED|skip) /) {
    print
  } else if (current != "") {
    output[current] = output[current] "\n" $0
  }
  next
}
!($1 in seen) {
  skipped[$1] = 1
  next
}
{
  found = 0
  present = 0
  actual = ""
  n = split(output[$1 SUBSEP $2], lines, "\n")
  for (i = 1; i <= n; i++) {
    if (lines[i] == $5) found = 1
    if (lines[i] ~ /[^ ]/) present = 1
    if (lines[i] ~ /^    /) actual = lines[i]
  }
  if ($3 == "value") outcome = found ? "ok" : present ? "drift" : "missing"
  else if ($3 == "present") outcome = present ? "ok" : "missing"
  else outcome = present ? "present" : "ok"
  count[outcome]++
  if (outcome == "drift") print "drift    " $4 ": " trim(actual) ", expected " trim($5)
  else if (outcome != "ok") print outcome "  " $4
}
END {
  if (!("machine" in seen)) {
    print "nix-win: no results from Windows"
    exit 1
  }
  drift = count["drift"] + count["present"]
  printf "nix-win: %d ok, %d drift, %d missing", count["ok"], drift, count["missing"]
  for (s in skipped) printf ", %s not checked", s
  print ""
  exit (drift + count["missing"] > 0)
}
