# Design and measurements: fzf-paths.md.
source "${${(%):-%x}:A:h}/fzf-includes.zsh"

# Avoid per-pattern subprocess startup.
escape_regex() {
  REPLY=$1
  local character
  for character in '\' '[' ']' '.' '^' '$' '*' '+' '?' '(' ')' '{' '}' '|'; do
    REPLY=${REPLY//"$character"/\\$character}
  done
}

{
  # Bound CPU costs across large hosts.
  finder=(fd --threads 4 --hidden --type "$kind" --exclude .git --strip-cwd-prefix)
  patterns=()
  for directory in "${include_dirs[@]}"; do
    escape_regex "$directory"
    patterns+=("${REPLY}(/|$)")
  done
  if [[ $kind == f ]]; then
    for pattern in "${include_files[@]}"; do
      escape_regex "$pattern"
      # Wildcards cannot cross directory boundaries.
      REPLY=${REPLY//\\\*/'[^/]*'}
      REPLY=${REPLY//\\\?/'[^/]'}
      patterns+=("${REPLY}$")
    done
  fi
  if (( $#patterns )); then
    # Prune only the additional ignored-path scan.
    exclude_flags=()
    for directory in "${skip_dirs[@]}"; do
      exclude_flags+=(--exclude "$directory")
    done
    # fd matches physical paths, including symlinks.
    escape_regex "${${PWD:A}%/}/"
    scan_root=$REPLY
    # Explicit case avoids checkout-dependent smart-case matching.
    include_command=("${finder[@]}" --no-ignore --case-sensitive --full-path
      "${exclude_flags[@]}"
      "^${scan_root}([^/]+/)*(${(j:|:)patterns})")
    if [[ $kind == f ]]; then
      # Overlap file walks; buffer results separately.
      coproc "${include_command[@]}"
      scan_pid=$!
      exec {scan_fd}<&p
    fi
  fi
  "${finder[@]}"
  if (( $#patterns )); then
    if [[ $kind == f ]]; then
      # Drain separately to preserve complete output lines.
      cat <&$scan_fd
      exec {scan_fd}<&-
      # Propagate failures from the ignored-path scan.
      wait "$scan_pid"
    else
      # Parallel directory walks delayed initial results.
      "${include_command[@]}"
    fi
  fi
  # Flush first output without per-record writes.
} | awk '!seen[$0]++ { print; if (NR == 1) fflush() }'
