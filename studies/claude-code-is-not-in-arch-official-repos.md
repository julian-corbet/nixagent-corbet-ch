# `claude-code` is not in any upstream Arch repository — `pacman -Si` alone cannot tell you that

**Finding.** `claude-code` resolves cleanly under `pacman -Si` on a CachyOS system and is in **no**
upstream Arch repository at all. Marking it `aur = false` on that evidence would hand every plain
Arch consumer a pacman target that cannot resolve — which fails the whole transaction, not just
that package.

**Decided:** `lib/agents.nix`'s `cli.claude-code` entry carries `aur = true` (the floor, correct
upstream) plus `archRepoOn = [ "cachyos" ]`, and `modules/nixagent.nix` grew `nixagent.distro` to
resolve between them. It is the only entry in the catalogue whose correct list depends on the host.

## What was checked, and what each source actually knows

Verified 2026-08-07, three independent sources:

| Source | What it answers | Result for `claude-code` |
|---|---|---|
| `pacman -Si claude-code` on a CachyOS system | which repository **this host** resolves the name in | found — `Repository: cachyos`, 2.1.222-1 |
| `archlinux.org/packages/search/json/?name=claude-code` | whether **upstream Arch** packages it, any repo, any arch | **0 results** |
| `aur.archlinux.org/rpc/v5/info?arg[]=claude-code` | whether the AUR carries it | found — `PackageBase` `claude-code`, 2.1.220-1, maintained, ~87 votes |

The three other entries in the catalogue behave the way one would naively expect, which is exactly
what makes this one easy to get wrong by pattern-matching:

| Name | `pacman -Si` (CachyOS) | Upstream Arch | AUR |
|---|---|---|---|
| `gemini-cli` | `cachyos-extra-v3` | `extra`, 0.50.0-1 | absent |
| `openai-codex` | `cachyos-extra-v3` | `extra`, 0.146.1-1 | absent |
| `opencode` | `cachyos-extra-v3` | `extra`, 1.18.14-1 | absent |
| `claude-code` | `cachyos` | **absent** | present |

Note the repository names. `cachyos-extra-v3` is CachyOS's own microarchitecture rebuild *of Arch's
`extra`* — a name found there is an upstream Arch package, recompiled. `cachyos` is CachyOS's
**own** repository: packages that exist because that derivative chose to ship them, with no
upstream Arch counterpart. The distinction is invisible to `pacman -Si`'s success/failure, which is
the whole trap: both look like "found in a repository."

## Why the direction of the error matters so much

`pacman -S` resolves a transaction **atomically**. One unresolvable target aborts the entire
converge with `target not found`, and every unrelated package in the same list is not installed
either. A reconciler that hands pacman a catalogue's worth of names in one call therefore has a
single-point failure per wrong `aur` flag — a mislabelled agent CLI takes the whole package set
down with it, on a host that may have nothing to do with agent CLIs.

The opposite error is cheap. Putting a repository package on the AUR list costs a trip through the
AUR helper, which resolves repository packages before building anything from source and finds it
immediately. Nothing is built, nothing fails.

So the two mistakes are not symmetric, and the design follows the asymmetry:

- `aur = true` is the **floor** for anything upstream Arch does not package.
- `archRepoOn` lifts it to the pacman list only on a distro whose own repository is known to carry
  it, and only when the host says it runs that distro.
- `nixagent.distro` defaults to `"arch"` — the recoverable answer — rather than to the distro the
  catalogue happened to be written on.

## Consequence for verification

A `pacman -Si` hit is **not** sufficient evidence for `aur = false` in this catalogue, and
`experiments/verify-package-names.sh` was written to enforce that: it treats archlinux.org's
package search as the authority for the official-repo claim, the AUR RPC as the authority for the
AUR claim, and `pacman -Si` as informational only — printed, never decisive.

`checks/agents-eval.nix` pins the resulting behaviour at eval time (claude-code on the AUR list
under `distro = "arch"`, on the pacman list under `distro = "cachyos"`, on exactly one list in both
cases), so a future edit cannot quietly flip it back.
