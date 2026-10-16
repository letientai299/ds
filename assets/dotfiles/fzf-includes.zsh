# Directory names included at any depth.
include_dirs=(
  .ai
  .dump
  local
)

# Filename patterns; supports * and ?.
include_files=(
  .envrc
  .exrc
  .nvim.lua
  .env
  '.env.*'
)

# Prune these during ignored-path scans.
skip_dirs=(
  node_modules vendor dist build target out bin obj Pods
  .git .svn .hg .tox .venv .cache .idea .vscode
)
