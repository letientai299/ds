source "${${(%):-%x}:A:h}/fzf-includes.zsh"
if (( $+commands[fd] )); then
  finder=$commands[fd]
elif (( $+commands[fdfind] )); then
  finder=$commands[fdfind]
else
  print -ru2 -- "${program}: fd is unavailable"
  exit 1
fi

{
  "$finder" --hidden --type "$kind" --exclude .git --strip-cwd-prefix

  patterns=()
  for directory in "${include_dirs[@]}"; do
    escaped=$(print -r -- "$directory" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    patterns+=("${escaped}(/|$)")
  done
  if [[ $kind == f ]]; then
    for pattern in "${include_files[@]}"; do
      escaped=$(print -r -- "$pattern" | sed \
        -e 's/[][\\.^$+(){}|]/\\&/g' \
        -e 's@\*@[^/]*@g' -e 's@?@[^/]@g')
      patterns+=("${escaped}$")
    done
  fi
  if (( $#patterns )); then
    exclude_flags=(--exclude .git)
    for directory in "${skip_dirs[@]}"; do
      exclude_flags+=(--exclude "$directory")
    done
    scan_root=$(print -r -- "${PWD%/}/" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    "$finder" --no-ignore --hidden --type "$kind" --full-path \
      --strip-cwd-prefix "${exclude_flags[@]}" \
      "^${scan_root}([^/]+/)*(${(j:|:)patterns})"
  fi
} | awk '!seen[$0]++'
