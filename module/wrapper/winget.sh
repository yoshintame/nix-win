bundle=${NIX_WIN_WINGET_BUNDLE:-$NIX_WIN_BUNDLE_FILE}
exe=${NIX_WIN_WINGET_EXE:-}
if [ -z "$exe" ]; then
  localappdata=$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /d /c 'echo %LOCALAPPDATA%' </dev/null | tr -d '\r')
  exe="$(wslpath -u "$localappdata")/Microsoft/WindowsApps/winget.exe"
fi

note() { echo "nix-win: $*" >&2; }

case ${1:-} in
install | add) action=add ;;
uninstall | remove | rm) action=remove ;;
*) exec "$exe" "$@" ;;
esac

args=("$@")
source=
scope=
for ((i = 1; i < ${#args[@]}; i++)); do
  case ${args[i]} in
  -s | --source) source=${args[i + 1]:-} ;;
  --source=*) source=${args[i]#--source=} ;;
  --scope) scope=${args[i + 1]:-} ;;
  --scope=*) scope=${args[i]#--scope=} ;;
  esac
done
if [ "$action" = add ] && [ -z "$scope" ]; then
  args+=(--scope machine)
  scope=machine
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
set +e
"$exe" "${args[@]}" | tee "$log"
code=${PIPESTATUS[0]}
set -e

found=$(tr '\r' '\n' <"$log" | grep -E '^Found .* \[[^]]+\]' | tail -n 1 || true)
id=$(sed -E 's/.*\[([^]]+)\][^[]*$/\1/' <<<"$found")
name=$(sed -E 's/^Found (.*) \[[^]]+\].*$/\1/' <<<"$found")
if [ -z "$id" ]; then
  exit "$code"
fi

if [ "$action" = add ]; then
  if [ "$code" -ne 0 ] && ! grep -qE 'already installed|No available upgrade found|No newer package versions' "$log"; then
    exit "$code"
  fi
else
  if [ "$code" -ne 0 ] && ! grep -q 'Successfully uninstalled' "$log"; then
    exit "$code"
  fi
fi

[ -f "$bundle" ] || echo '{}' >"$bundle"
inBundle=$(jq --arg id "$id" 'has($id)' "$bundle")
declared=false
if grep -qxF -- "$id" <<<"$NIX_WIN_DECLARED" && [ "$inBundle" = false ]; then declared=true; fi

edit() {
  local next
  next=$(mktemp "$bundle.XXXXXX")
  jq -S "$@" "$bundle" >"$next"
  mv "$next" "$bundle"
}

if [ "$action" = add ]; then
  if [ "$scope" != machine ]; then
    note "$id is installed with --scope $scope; the bundle holds machine-wide packages only, so it is not recorded"
  elif $declared; then
    note "$id is declared in a Nix module; the bundle is left as is"
  else
    if [ -z "$source" ]; then
      source=$("$exe" list --id "$id" --exact --disable-interactivity </dev/null | tr -d '\r' | awk -v id="$id" 'index($0, id) { print $NF }' | tail -n 1)
    fi
    if [ "$source" = msstore ]; then
      edit --arg id "$id" --arg name "$name" '.[$id] = ((.[$id] // {}) + { source: "msstore", name: $name })'
    else
      edit --arg id "$id" '.[$id] = (.[$id] // {})'
    fi
    note "recorded $id in $bundle"
  fi
elif [ "$inBundle" = true ]; then
  edit --arg id "$id" 'del(.[$id])'
  note "removed $id from $bundle"
elif $declared; then
  note "$id is declared in a Nix module; remove it there, or the next switch --winget installs it again"
fi
exit "$code"
