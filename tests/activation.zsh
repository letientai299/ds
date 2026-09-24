cd "$DS_TEST_WORK/one"
source "$DS_TEST_SRC/dotfiles/shell.zsh"
if [[ $DS_MISE_ACTIVATE == 0 ]]; then
  [[ -z ${DS_TEST_PROJECT:-} && -z ${_ds_mise_loaded:-} ]] || exit 1
  exit
fi
[[ $DS_TEST_PROJECT == one ]] || exit 2
cd "$DS_TEST_WORK/two"
[[ $DS_TEST_PROJECT == two ]] || exit 3
source "$DS_TEST_SRC/dotfiles/shell.zsh"
[[ ${#chpwd_functions} == ${#${(u)chpwd_functions}} ]] || exit 4
[[ ${#precmd_functions} == ${#${(u)precmd_functions}} ]] || exit 5
cd "$DS_TEST_WORK"
[[ -z ${DS_TEST_PROJECT:-} ]] || exit 6
