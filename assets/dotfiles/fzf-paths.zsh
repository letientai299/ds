source "${${(%):-%x}:A:h}/fzf-includes.zsh"

escape_regex() {
  REPLY=$1
  local character
  for character in '\' '[' ']' '.' '^' '$' '*' '+' '?' '(' ')' '{' '}' '|'; do
    REPLY=${REPLY//"$character"/\\$character}
  done
}

{
  patterns=()
  for directory in "${include_dirs[@]}"; do
    escape_regex "$directory"
    patterns+=("${REPLY}(/|$)")
  done
  if [[ $kind == f ]]; then
    for pattern in "${include_files[@]}"; do
      escape_regex "$pattern"
      REPLY=${REPLY//\\\*/'[^/]*'}
      REPLY=${REPLY//\\\?/'[^/]'}
      patterns+=("${REPLY}$")
    done
  fi
  if (( $#patterns )); then
    exclude_flags=(--exclude .git)
    for directory in "${skip_dirs[@]}"; do
      exclude_flags+=(--exclude "$directory")
    done
    escape_regex "${${PWD:A}%/}/"
    scan_root=$REPLY
    include_command=(fd --no-ignore --hidden --type "$kind" --full-path
      --strip-cwd-prefix "${exclude_flags[@]}"
      "^${scan_root}([^/]+/)*(${(j:|:)patterns})")
    if [[ $kind == f ]]; then
      coproc "${include_command[@]}"
      scan_pid=$!
      exec {scan_fd}<&p
    fi
  fi
  fd --hidden --type "$kind" --exclude .git --strip-cwd-prefix
  if (( $#patterns )); then
    if [[ $kind == f ]]; then
      # Drain separately to preserve complete output lines.
      cat <&$scan_fd
      exec {scan_fd}<&-
      wait "$scan_pid"
    else
      # Preserve first-result latency on directory scans.
      "${include_command[@]}"
    fi
  fi
} | awk '!seen[$0]++ { print; if (NR == 1) fflush() }'
