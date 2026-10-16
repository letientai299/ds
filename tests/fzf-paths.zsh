#!/bin/zsh -df
setopt err_exit pipe_fail
root=${0:A:h:h}
artifact_dir="$root/.ai/fzf-includes${LC_SSH_ALIAS:+/$LC_SSH_ALIAS}"
mkdir -p "$artifact_dir"
work=$(mktemp -d "$artifact_dir/test.XXXXXX")
trap 'cd "$root"; rm -rf "$work"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
mkdir -p "$work/helpers/tools" "$work/helpers/dotfiles" "$work/local/repo[1]+"
cp "$root"/assets/tools/fzf-{files,dirs} "$work/helpers/tools/"
cp "$root"/assets/dotfiles/fzf-{paths,includes}.zsh "$work/helpers/dotfiles/"
cd "$work/local/repo[1]+"
git init -q
print -rl -- 'local/' '.ai/' '.dump/' '.env*' 'ignored/' 'node_modules/' > .gitignore
files=(
  normal.txt local/root.txt nested/local/settings/config.lua
  .ai/notes.txt nested/.dump/log.txt .env nested/.env
  nested/.env.production ignored/deep/.env local/.env
)
omitted=(ignored/secret.txt ignored/LOCAL/hidden.txt ignored/.ENV node_modules/local/hidden.txt node_modules/.env)
for file in "${files[@]}" "${omitted[@]}"; do
  mkdir -p "${file:h}"
  touch "$file"
done
fail() { print -ru2 -- "fzf: $*"; exit 1; }
files_helper="$work/helpers/tools/fzf-files"
check_files() {
  local -a actual unique
  local file
  actual=("${(@f)$("$files_helper")}")
  unique=("${(@u)actual}")
  (( $#actual == $#unique )) || fail 'duplicate files'
  for file in "${files[@]}"; do
    (( ${actual[(Ie)$file]} )) || fail "missing $file"
  done
  for file in "${omitted[@]}"; do
    (( ! ${actual[(Ie)$file]} )) || fail "included $file"
  done
}
check_files
mkdir -p "$work/case-tools"
cat > "$work/case-tools/fd" <<'SH'
#!/bin/sh
exec "$FZF_REAL_FD" --ignore-case "$@"
SH
chmod +x "$work/case-tools/fd"
(
  # Uppercase roots conceal fd's default smart-case.
  export FZF_REAL_FD=${commands[fd]}
  export PATH="$work/case-tools:$PATH"
  check_files
)
ln -s "$PWD" "$work/linked"
ln -s "$files_helper" "$work/linked-files"
files_helper="$work/linked-files"
cd "$work/linked"
check_files
actual=("${(@f)$("$work/helpers/tools/fzf-dirs")}")
unique=("${(@u)actual}")
(( $#actual == $#unique )) || fail 'duplicate directories'
for directory in local/ nested/local/ nested/local/settings/ .ai/ nested/.dump/; do
  (( ${actual[(Ie)$directory]} )) || fail "missing $directory"
done
for directory in ignored/ node_modules/local/ .env nested/.env; do
  (( ! ${actual[(Ie)$directory]} )) || fail "included $directory"
done

literal='custom[1]+(x)$^.*?|\'
mkdir -p "ignored/$literal"
touch "ignored/$literal/file.txt" ignored/file1.cfg ignored/file12.cfg
print -r -- "include_dirs+=( ${(q)literal} )" >> "$work/helpers/dotfiles/fzf-includes.zsh"
print -r -- "include_files+=( 'file?.cfg' )" >> "$work/helpers/dotfiles/fzf-includes.zsh"
files+=("ignored/$literal/file.txt" ignored/file1.cfg)
omitted+=(ignored/file12.cfg)
check_files
print -rl -- 'include_dirs=()' 'include_files=()' >> "$work/helpers/dotfiles/fzf-includes.zsh"
files=(normal.txt .gitignore)
omitted+=(local/root.txt nested/local/settings/config.lua .env nested/.env)
check_files
cp "$root/assets/dotfiles/fzf-includes.zsh" "$work/helpers/dotfiles/"
mkdir -p "$work/tools"
cat > "$work/tools/fd" <<'SH'
#!/bin/sh
case " $* " in
  *' --no-ignore '*) [ "$FZF_FAIL_MODE" != ignored ] || exit 23 ;;
  *) [ "$FZF_FAIL_MODE" != base ] || exit 19 ;;
esac
printf '%s\n' normal.txt
SH
chmod +x "$work/tools/fd"
for mode code in ignored 23 base 19; do
  failure_code=0
  PATH="$work/tools:$PATH" FZF_FAIL_MODE=$mode "$work/helpers/tools/fzf-files" > /dev/null || failure_code=$?
  (( failure_code == code )) || fail "$mode error lost"
done
print -r -- 'fzf path tests passed'
