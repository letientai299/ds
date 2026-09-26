zmodload zsh/zpty

installer=$1
prefix=$2
answer=$3
transcript=$4
zpty -b installer "sh ${(q)installer} --prefix ${(q)prefix} --layer extra --no-apply; print -r -- result=\$?"
trap 'zpty -d installer' EXIT
output=
prompted=false
for attempt in {1..300}; do
    while zpty -r installer chunk '*'; do
        output+=$chunk
    done
    if [[ $prompted == false && $output == *' [y/N] '* ]]; then
        zpty -w -n installer "$answer"$'\n'
        prompted=true
    fi
    if [[ $output == *'result=0'* ]]; then
        print -r -- "$output" >"$transcript"
        [[ $prompted == true ]] || exit 1
        exit 0
    fi
    sleep 0.05
done
print -r -- "$output" >"$transcript"
exit 1
