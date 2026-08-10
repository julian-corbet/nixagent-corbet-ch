# Three vendor installers, three prefixes, and one that changes its mind — why `upstream` is a per-entry record

**Finding.** The three catalogued vendor installers were read line by line on 2026-08-10. They
agree on the interface they present (`curl -fsSL <url> | sh`) and on nothing else. One installs to
`~/.local/bin`, one to `~/.opencode/bin`, and one picks its destination at runtime based on whether
an *unrelated* tool is installed on the machine. Two of them edit files outside their prefix.

**Decided:** `upstream` in `lib/agents.nix` is a per-entry record of `url` / `runner` / `args` /
`installs`, not a module-wide `prefix` option; two entries carry mandatory flags; and
`lib/install-upstream.sh` downloads to a file instead of piping into a shell.

## What each installer actually does

### `claude.ai/install.sh` — bash, `~/.local/bin/claude`

Downloads a versioned binary into `~/.claude/downloads`, fetches the release manifest, verifies a
SHA-256 checksum against it, runs `<binary> install`, deletes the download. Refuses to run under
`sudo` from a user shell (it would install into root's home) unless
`CLAUDE_INSTALL_ALLOW_SUDO=1`. Takes an optional `stable|latest|VERSION` argument and defaults to
latest.

The launcher path is **not visible in the script** — it is decided inside the downloaded binary's
own `install` subcommand. The catalogue's `installs = ".local/bin/claude"` is therefore taken from
a host where this installer was actually used (`~/.local/bin/claude` → `~/.local/share/claude/
versions/<version>`), not read out of the script. That is exactly the kind of value that goes
stale silently, which is why `lib/install-upstream.sh` verifies the path exists *and* answers
`--version` after the installer returns rather than trusting the record.

### `omp.sh/install` — POSIX `sh`, `~/.local/bin/omp` **only if you force it**

The destination depends on the *host*, not on the tool:

```sh
INSTALL_DIR="${PI_INSTALL_DIR:-$HOME/.local/bin}"
...
# Default: use bun only when it matches the host architecture, otherwise
# fall back to the prebuilt binary
if has_bun && bun_arch_matches_host; then
    install_via_bun          # -> bun install -g, lands in $BUN_INSTALL/bin
else
    install_binary           # -> curl -o "${INSTALL_DIR}/omp"
fi
```

So on a machine that happens to have `bun`, `omp` is installed by `bun install -g` into bun's own
global prefix (`~/.bun/bin` by default). On a machine without it, into `~/.local/bin`. Same
command, same URL, different file.

This is the finding that made `args` a field rather than a nicety. An idempotency probe on
`~/.local/bin/omp` would be correct on one host and *permanently unsatisfied* on the next — where
the module would reinstall on every single activation, reporting success every time, which is the
"cheap and idempotent" requirement inverted into its worst case. `--binary` forces the branch whose
destination the catalogue can state. It also stops the installer from installing `bun` as a side
effect, which a module asked for `omp` has no business doing.

Its own post-install smoke test is worth stealing, and was:

```sh
# Never claim success for a binary that cannot run.
if ! SMOKE_OUTPUT="$("${INSTALL_DIR}/omp" --version 2>&1)"; then
```

A Bun musl-target binary downloads fine and then dies with relocation errors because
libstdc++/libgcc are absent. The download succeeding proves nothing. `lib/install-upstream.sh` runs
the same `--version` check for every tool for the same reason.

### `opencode.ai/install` — bash, `~/.opencode/bin/opencode`, and it edits your shell rc

```sh
INSTALL_DIR=$HOME/.opencode/bin
```

Hard-coded, honouring no environment variable. This single line is why there is no module-wide
`prefix` option: two of three installers use `~/.local/bin` and this one does not, and none of them
can be told otherwise. A `nixagent.home.prefix` would be an option that appears to steer something
it cannot.

It then walks `$HOME/.bashrc`, `$HOME/.bash_profile`, `$XDG_CONFIG_HOME/bash/...` (or the zsh/fish
equivalents), takes the first that exists, and appends a PATH line to it. On a home-manager-managed
home those files are generated, so the edit is either discarded at the next switch or silently
fights it. `--no-modify-path` suppresses it, and `nixagent.home.addToPath` publishes the directory
through `home.sessionPath` instead — declaratively, where it survives.

## The two entries with no installer, and why npm was not accepted as one

`gemini-cli` and `openai-codex` carry `upstream = null`. Checked 2026-08-10:
`gemini.google.com/install.sh` → **404**, the repository's own `install.sh` on `main` → **404**,
`openai.com/codex/install.sh` → **403**. Both projects distribute through npm and Homebrew plus
per-release binaries with no script to place them.

`npm install -g` was considered and rejected as an upstream mode. It installs into whichever node
prefix is configured — a nix-store node's is read-only, a system node's is root-owned, an nvm
node's moves with the active version — so the path this catalogue would have to record as
`installs` is a property of the host's node setup rather than of the tool. That is precisely the
ambiguity `omp`'s bun branch demonstrates, generalised, and there is no `--binary` equivalent to
resolve it.

`claude-cowork-linux` carries `upstream = null` structurally: the AUR package is a third party's
repackaging of a proprietary Electron application, so there is no vendor per-user installer to run
at all.

## `curl | sh` is not safe to run from an activation script

Every one of these vendors documents the pipe form. It must not be used here, for a reason that has
nothing to do with trusting the vendor.

A pipeline's exit status is its **last** command's. When the fetch fails — DNS, captive portal,
proxy, 404 — curl's status is discarded, the (empty or HTML) body is handed to `sh`, which reads
it, finds nothing to run, and exits **0**. The activation then reports success having installed
nothing. `set -o pipefail` fixes the status case but not the "HTTP 200 with an HTML error page"
case, which `curl -f` cannot reject either.

Downloading to a file first makes curl's own status the answer *and* allows the content to be
inspected before it is executed — `lib/install-upstream.sh` refuses anything whose first line is
not `#!` and prints the first five lines of what did arrive. Both behaviours have a test in
`checks/upstream-install.nix`; removing either is caught.

## What this leaves as the catalogue's job

> Record what the vendor's installer *does* — its URL, the interpreter it needs, the flags that
> make its destination deterministic, and the path it ends up creating. Do not attempt to change
> any of it.

Everything the module knows about where a tool lands comes from that record, and the record is
verified against reality after every install rather than trusted.
