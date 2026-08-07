# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
file below.

- `verify-package-names.sh` — the catalogue's load-bearing verification: every `arch` name in
  `../lib/agents.nix` checked against **upstream Arch** (archlinux.org's package search API, the
  authority for an `aur = false` claim), the **AUR RPC** (the authority for `aur = true`), and
  `pacman -Si` on the running host (informational only — see
  [`../studies/claude-code-is-not-in-arch-official-repos.md`](../studies/claude-code-is-not-in-arch-official-repos.md)
  for the entry that proves why it cannot be the authority). Reads the names out of the catalogue
  rather than a second hand-kept list.

## Why this lives here and not in `checks/`

`checks/` is `nix flake check`-wired and evaluates offline: it can prove how the module *resolves*
a selection, and it does — including the invariant that the pacman and AUR lists never intersect.
It cannot prove that `claude-code` is in a given repository **today**. That is a fact about the
world; it changes without this repo changing, and asserting it at eval time would either need
network access from a pure evaluation or a snapshot that silently goes stale.

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
