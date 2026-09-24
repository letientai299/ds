# Third-party notices

A `ds` snapshot redistributes two prebuilt binaries. Both are MIT-licensed, and
MIT requires this notice to travel with the copies, so this file ships inside
every snapshot and release archive.

Tools that `mise` installs at apply time are downloaded on the target from their
own upstreams and are not redistributed here; they remain under their own
licenses.

Vendored `nvim.conf` and `tmux.conf` trees are Git exports of the sibling
checkouts named at build time and carry whatever license those repositories do.

## Oh My Zsh

`src/dotfiles/omz` contains shell code from the Oh My Zsh checkout used by the
old dotfiles configuration, at commit
`74965c96098134b192f00084f966b4b02438a739`. Its MIT [license][omz-license] ships
beside the code in every snapshot.

The port includes the Git plugin, its current-branch and clipboard helpers,
directory shortcuts, and Docker aliases. Completion bindings are conditional
on `compdef` being available. Docker completion generation and Git prompt hooks
are omitted so the aliases work without Oh My Zsh startup or cache directories.
Personal overrides live in [`aliases.zsh`][aliases].

## Interactive Zsh plugins

`src/dotfiles/plugins` contains the runtime sources from the old dotfiles'
plugin checkouts. Each plugin's `REVISION` records its upstream commit.
Sources and licenses travel together in every snapshot:

- `zsh-defer`: GPL-3.0, see its `LICENSE`.
- `zsh-autosuggestions`: MIT, see its `LICENSE`.
- `fzf-tab`: MIT, see its `LICENSE` and `lib/zsh-ls-colors/LICENSE`.
- `zsh-syntax-highlighting`: BSD-3-Clause, see its `COPYING.md`.

[`interactive.zsh`][interactive] loads completion and these plugins after the
first prompt, in dependency order. Shell startup needs no plugin downloads.

## Janet

The pinned Janet runtime is compiled from the upstream amalgamation and shipped
as `src/runtime/bin/<platform>/janet`. See [janet-lang/janet][janet].

```text
Copyright (c) Calvin Rose and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## mise

The pinned mise release binary is shipped as
`src/runtime/bin/<platform>/mise`. See [jdx/mise][mise].

```text
Copyright (c) Jeff Dickey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

[janet]: https://github.com/janet-lang/janet
[mise]: https://github.com/jdx/mise
[omz-license]: dotfiles/omz/LICENSE.txt
[aliases]: dotfiles/aliases.zsh
[interactive]: dotfiles/interactive.zsh
