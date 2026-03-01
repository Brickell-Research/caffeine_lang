#!/bin/sh
# Lines-of-code report per module (cloc-style)

lang_name() {
  case $1 in
    gleam) echo Gleam;;
    mjs)   echo JavaScript;;
    ts)    echo TypeScript;;
    toml)  echo TOML;;
    json)  echo JSON;;
    *)     echo "$1";;
  esac
}

comment_pattern() {
  case $1 in
    gleam)     echo '^ *///';;
    mjs|ts|js) echo '^ *//';;
    toml)      echo '^ *#';;
    *)         echo 'NOMATCH_PATTERN';;
  esac
}

SEP="------------------------------------------------------"
total_files=0; total_blank=0; total_comment=0; total_code=0

for mod in caffeine_lang caffeine_lsp caffeine_cli; do
  printf "\n%s\n" "$mod"
  printf "%-14s %8s %8s %8s %8s\n" "Language" "Files" "Blank" "Comment" "Code"
  printf "%s\n" "$SEP"

  mod_files=0; mod_blank=0; mod_comment=0; mod_code=0

  for ext in gleam mjs ts toml json; do
    files=$(find "$mod/src" "$mod/test" -name "*.$ext" -not -path '*/build/*' 2>/dev/null)
    [ -z "$files" ] && continue

    nfiles=$(echo "$files" | wc -l | tr -d ' ')
    blank=$(echo "$files" | xargs grep -c '^$' 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')

    pat=$(comment_pattern "$ext")
    if [ "$pat" = "NOMATCH_PATTERN" ]; then
      comment=0
    else
      comment=$(echo "$files" | xargs grep -c "$pat" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
    fi

    lines=$(echo "$files" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    code=$((lines - blank - comment))
    lang=$(lang_name "$ext")

    printf "%-14s %8s %8s %8s %8s\n" "$lang" "$nfiles" "$blank" "$comment" "$code"

    mod_files=$((mod_files + nfiles))
    mod_blank=$((mod_blank + blank))
    mod_comment=$((mod_comment + comment))
    mod_code=$((mod_code + code))
  done

  printf "%s\n" "$SEP"
  printf "%-14s %8s %8s %8s %8s\n" "Total" "$mod_files" "$mod_blank" "$mod_comment" "$mod_code"

  total_files=$((total_files + mod_files))
  total_blank=$((total_blank + mod_blank))
  total_comment=$((total_comment + mod_comment))
  total_code=$((total_code + mod_code))
done

printf "\n%s\n" "All modules"
printf "%s\n" "$SEP"
printf "%-14s %8s %8s %8s %8s\n" "Grand Total" "$total_files" "$total_blank" "$total_comment" "$total_code"
