# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
file below.

- `verify-package-names.sh` — the catalogue's load-bearing verification, for **both** delivery
  modes:
  - every `arch` name in `../lib/agents.nix` checked against **upstream Arch** (archlinux.org's
    package search API, the authority for an `aur = false` claim), the **AUR RPC** (the authority
    for `aur = true`), and `pacman -Si` on the running host (informational only — see
    [`../studies/claude-code-is-not-in-arch-official-repos.md`](../studies/claude-code-is-not-in-arch-official-repos.md)
    for the entry that proves why it cannot be the authority);
  - every AUR package's **version and out-of-date flag**, printed as a `WARN` rather than a
    failure. The name is still right; what a flag means is that this entry's *distro* plane has
    stopped tracking upstream, which is the finding behind
    [`../studies/the-aur-lags-upstream-too.md`](../studies/the-aur-lags-upstream-too.md) and the
    signal that a host wanting the tool current belongs on `nixagent.home.upstream`;
  - every `upstream.url` **fetched**, and its first line checked for a `#!`. A vendor installer can
    404, move, or start answering with an HTML error page without anything in this repo changing.

  Reads all of it out of the catalogue rather than a second hand-kept list.

## Why this lives here and not in `checks/`

`checks/` is `nix flake check`-wired and evaluates offline: it can prove how the module *resolves*
a selection, and it does — including the invariant that the pacman and AUR lists never intersect.
It cannot prove that `claude-code` is in a given repository **today**, or that
`https://omp.sh/install` still answers. Those are facts about the world; they change without this
repo changing, and asserting them at eval time would either need network access from a pure
evaluation or a snapshot that silently goes stale.

`checks/upstream-install.nix` is the one check that *runs* rather than evaluates, and it still
belongs there rather than here: it stubs the network on purpose, so what it proves is the
installer script's **behaviour** (it does not re-fetch when the tool is present; every failure
mode is visible), which is deterministic and offline. Whether the real URL is up is this
directory's question.

So the split is deliberate and matches what every sibling repo in this family does with its own
name verification: eval-time checks for anything internal and deterministic, a hand-run script for
anything that depends on what upstream is shipping this week.

## What is deliberately NOT verified here

There is no nixpkgs-resolution script, unlike the sibling repos' versions of this directory.
Nothing in this catalogue names a nixpkgs attribute — `nixpkgs = null` is the policy, not an
absence, and it is enforced at eval time by `../checks/agents-eval.nix` rather than checked against
a package set. See [`../lib/agents.nix`](../lib/agents.nix)'s header for the measurements behind
that policy (all four tools exist in nixpkgs; all four lag the distro package, and all four ship
their own updater that a read-only store path cannot run).

If something in here turns out to matter in a different way, distil the actual finding into
[`../studies/`](../studies/README.md) and let the experiment stay disposable (or delete it).

See the main [README](../README.md) for the project itself.
