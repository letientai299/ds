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

  # Restrict ignored scans to explicit roots.
  search_paths=()
  for directory in "${include_dirs[@]}"; do
    [[ ! -d $directory ]] || search_paths+=(--search-path "$directory")
  done
  if (( $#search_paths )); then
    "$finder" --no-ignore --hidden --type "$kind" --exclude .git "${search_paths[@]}"
  fi

  if [[ $kind == f ]]; then
    for pattern in "${include_files[@]}"; do
      for file in ./${~pattern}(N); do
        [[ ! -f $file ]] || print -r -- "${file#./}"
      done
    done
  else
    for directory in "${include_dirs[@]}"; do
      [[ ! -d $directory ]] || print -r -- "$directory/"
    done
  fi
} | awk '!seen[$0]++'
