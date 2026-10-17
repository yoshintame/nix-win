mkdir -p "$out"
n=$(jq length "$specPath")
for ((i = 0; i < n; i++)); do
  path=$(jq -r ".[$i].path" "$specPath")
  mkdir -p "$out/$(dirname "$path")"
  case $(jq -r ".[$i].encoding" "$specPath") in
    utf16) { printf '\xff\xfe'; jq -j ".[$i].text" "$specPath" | iconv -f UTF-8 -t UTF-16LE; } >"$out/$path" ;;
    copy) cp "$(jq -r ".[$i].source" "$specPath")" "$out/$path" ;;
    *) jq -j ".[$i].text" "$specPath" >"$out/$path" ;;
  esac
done
