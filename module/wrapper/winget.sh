bundle=${NIX_WIN_WINGET_BUNDLE:-$NIX_WIN_BUNDLE_FILE}
exe=${NIX_WIN_WINGET_EXE:-}
if [ -z "$exe" ]; then
  localappdata=$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /d /c 'chcp 65001 >nul & echo %LOCALAPPDATA%' </dev/null | tr -d '\r')
  exe="$(wslpath -u "$localappdata")/Microsoft/WindowsApps/winget.exe"
fi

note() { echo "nix-win: $*" >&2; }

case ${1:-} in
install | add) action=add ;;
uninstall | remove | rm) action=remove ;;
*) exec "$exe" "$@" ;;
esac

takesValue() {
  case $1 in
  --id | -q | --query | -s | --source | --scope | -m | --manifest | --name | --moniker | -v | --version | -a | --architecture | --installer-type | -l | --location | --locale | -o | --log | --override | --custom | --header | --authentication-mode | --authentication-account | --rename | --product-code | --dependency-source) return 0 ;;
  *) return 1 ;;
  esac
}

args=("$@")
ids=()
source=
scope=
manifest=false
for ((i = 1; i < ${#args[@]}; i++)); do
  arg=${args[i]}
  value=${args[i + 1]:-}
  case $arg in
  --id | -q | --query) ids+=("$value") ;;
  --id=* | --query=*) ids+=("${arg#*=}") ;;
  -s | --source) source=$value ;;
  --source=*) source=${arg#*=} ;;
  --scope) scope=${value,,} ;;
  --scope=*)
    scope=${arg#*=}
    scope=${scope,,}
    ;;
  -m | --manifest | --manifest=*) manifest=true ;;
  -*) ;;
  *) takesValue "${args[i - 1]}" || ids+=("$arg") ;;
  esac
done

if [ "$action" = add ] && [ -z "$scope" ]; then
  args+=(--scope machine)
  scope=machine
fi

reason=
if $manifest; then
  reason="installs from a manifest are not recorded"
elif [ ${#ids[@]} -ne 1 ]; then
  reason="the bundle is updated only for one package per command"
elif [ "$action" = add ] && [ "$scope" != machine ]; then
  reason="the bundle holds machine-wide packages only, so a --scope $scope install is not recorded"
elif [ -n "$source" ] && [ "$source" != winget ] && [ "$source" != msstore ]; then
  reason="packages from source $source are not recorded"
elif [ -s "$bundle" ] && ! jq -e 'type == "object"' "$bundle" >/dev/null 2>&1; then
  note "$bundle is not a JSON object; fix it before installing or uninstalling through this command"
  exit 1
fi

set +e
"$exe" "${args[@]}"
code=$?
set -e

if [ -n "$reason" ]; then
  note "$reason"
  exit "$code"
fi
id=${ids[0]}

listed() {
  "$exe" list --id "$id" --exact "$@" --accept-source-agreements --disable-interactivity </dev/null | tr -d '\r' |
    awk -v id="$id" 'BEGIN { id = tolower(id) } { for (i = 2; i <= NF; i++) if (tolower($i) == id) { name = $1; for (j = 2; j < i; j++) name = name " " $j; print $i "\t" name "\t" $NF; exit } }' || true
}

if grep -qixF -- "$id" <<<"$NIX_WIN_DECLARED"; then
  if [ "$action" = add ]; then
    note "$id is declared in a Nix module; the bundle is left as is"
  elif [ -z "$(listed)" ]; then
    note "$id is declared in a Nix module; remove it there, or the next switch --winget installs it again"
  fi
  exit "$code"
fi

update() {
  local next current
  next=$(mktemp)
  exec 9<>"$bundle"
  flock 9
  current=$(cat "$bundle")
  if jq -S "$@" <<<"${current:-"{}"}" >"$next"; then
    cat "$next" >"$bundle"
  fi
  rm -f "$next"
}
key='((keys | map(select(ascii_downcase == ($id | ascii_downcase))) | first) // $id)'

if [ "$action" = add ]; then
  IFS=$'\t' read -r canonical name found <<<"$(listed --scope machine)"
  if [ -z "${canonical:-}" ]; then
    note "$id is not installed machine-wide under that exact ID; pass the package ID with --id to record it"
    exit "$code"
  fi
  source=${source:-$found}
  case $source in
  winget) update --arg id "$canonical" ".[$key] = (.[$key] // {})" ;;
  msstore) update --arg id "$canonical" --arg name "$name" ".[$key] = ((.[$key] // {}) + { source: \"msstore\", name: \$name })" ;;
  *)
    note "$canonical comes from source ${source:-unknown}, not recorded"
    exit "$code"
    ;;
  esac
  note "recorded $canonical in $bundle"
elif [ -z "$(listed)" ] && [ -s "$bundle" ] && [ "$(jq --arg id "$id" "$key as \$k | has(\$k)" "$bundle")" = true ]; then
  update --arg id "$id" "del(.[$key])"
  note "removed $id from $bundle"
fi
exit "$code"
