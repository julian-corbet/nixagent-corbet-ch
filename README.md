# nixagent

**Agentic AI CLIs — Claude Code, Gemini CLI, Codex, opencode — declared per host, on the hosts that
actually want them, and installed from pacman/AUR rather than nixpkgs because they update
themselves.**

## What this is

A platform-neutral catalogue (`lib/agents.nix`) naming each agent CLI's package identity and its
real command name, plus one module (`modules/nixagent.nix`) that resolves a selection into two
lists a host's Arch package reconciler can consume:

```nix
nixagent.distro = "cachyos";               # or "arch" (the default)
nixagent.cli = [ "claude-code" "gemini-cli" "openai-codex" "opencode" ];

nixarch.packages.pacman = config.nixagent.archPackages;
nixarch.packages.aur    = config.nixagent.aurPackages;
```

That is the whole surface. One top-level option namespace, `nixagent`, like every repo in this
family.

## The rule this repo exists for: pacman/AUR always, nixpkgs never

These tools **ship their own updater** and release on a cadence measured in days. A nix-store path
is read-only, so the updater cannot run at all — the version freezes until a human bumps a
`flake.lock`, and the tool spends the interval telling its operator to update while being
structurally unable to. A distro package is mutable enough that the system's own upgrade *is* the
updater, which is the outcome you want.

nixpkgs also lags them, and that half is measured rather than asserted. Force-evaluated against a
pinned revision on 2026-08-07:

| Catalogue entry | nixpkgs | pacman |
|---|---|---|
| `claude-code` | `pkgs.claude-code` 2.1.220 | 2.1.222-1 |
| `gemini-cli` | `pkgs.gemini-cli` 0.47.0 | 0.50.0-1 |
| `openai-codex` | `pkgs.codex` 0.146.0 | 0.146.1-1 |
| `opencode` | `pkgs.opencode` 1.18.11 | 1.18.14-1 |

So availability is not the reason — nixpkgs carries all four. The reason is that a nixpkgs
derivation pins and hashes a release, which is precisely the property this class of tool is built
to defeat.

The catalogue therefore carries **`nixpkgs = null` on every entry**, present rather than omitted so
that nobody mistakes the policy for an oversight, and `checks/agents-eval.nix` asserts it — an
addition that names a real nixpkgs attribute fails `nix flake check`. There is **no `nixosModules`
output**: not a gap to fill later, but the boundary the repo was drawn for.

## Why these are not nixllm's, and not nixsh's

Package delivery in this family is split by **domain**, and these four had no owner.

**Not [nixllm](https://github.com/julian-corbet/nixllm-corbet-ch).** That repo *serves* models — a
broker, an inference engine, a model store, a GPU. Everything here is an HTTPS client that never
loads a weight and has no opinion about a GPU. Same project space, opposite side of the wire, and a
shared catalogue would mean one repo whose entries need two unrelated kinds of host to be useful.

**Not [nixsh](https://github.com/julian-corbet/nixsh-corbet-ch)**, despite these being terminal
tools. nixsh is universal *by construction* — every host has a shell and reaches for a terminal
tool, which is exactly why that catalogue has no per-host story to build. These do not have that
property and must not inherit it: a small production server has a shell and wants `ripgrep`, and
emphatically does not want a self-updating agent CLI and its runtime. "Runs in a terminal" is a
shape; nixsh's claim is the *domain* "every host needs this", and these fail it.

The placement rule, stated in `lib/agents.nix`'s own header so the next candidate is decidable
rather than argued:

> Does the tool drive a model it does not host, from a terminal, with no window of its own? Yes →
> here. No → whichever repo owns the thing it actually is.

## The AUR/pacman split, and why it is not the same answer on every host

`pacman -S` resolves a transaction **atomically**: one unresolvable target aborts the whole
converge with `target not found` and takes every unrelated package in the same list down with it.
So `archPackages` and `aurPackages` are separate outputs, and that they never intersect is the
load-bearing invariant `checks/` exists to hold.

One entry makes this harder than it looks. `claude-code` is in **no upstream Arch repository** —
archlinux.org's package search returns nothing for it — but it *is* in the AUR, and CachyOS's own
repository carries it too. It resolves cleanly under `pacman -Si` on a CachyOS box, which is
exactly the observation that would tempt you into `aur = false` and hand every plain Arch consumer
a broken transaction.

The two errors are not symmetric, so the design follows the asymmetry:

- `aur = true` is the **floor** for anything upstream Arch does not package — the direction that
  cannot abort a transaction, since an AUR helper resolves repository packages first and builds
  nothing that did not need building.
- `archRepoOn = [ "cachyos" ]` lifts it to the pacman list, but only on a distro whose own
  repository is known to carry it.
- `nixagent.distro` defaults to `"arch"`, the recoverable answer, rather than to whichever distro
  the catalogue happened to be written on.

Write-up with the full evidence:
[`studies/claude-code-is-not-in-arch-official-repos.md`](studies/claude-code-is-not-in-arch-official-repos.md).

## Package name ≠ command name

Three of the four disagree, so `nixagent.binaries` publishes the mapping. Pointing an alias, a
wrapper or a home-manager config at the *package* name gets you a command that does not exist.

| Selection | pacman package | command |
|---|---|---|
| `claude-code` | `claude-code` | `claude` |
| `gemini-cli` | `gemini-cli` | `gemini` |
| `openai-codex` | `openai-codex` | `codex` |
| `opencode` | `opencode` | `opencode` |

## What this does not own

- **Configuration of the agents themselves** — API keys, model choice, MCP servers, permission
  rules. This repo installs binaries and publishes names; per-user agent config is home-manager's
  job, and lives wherever the consumer already keeps it.
- **Desktop applications.** `claude-cowork-linux` was evaluated and excluded: it depends on
  `electron` and installs a `.desktop` entry with `Type=Application` and `StartupWMClass=Claude`,
  where every catalogued entry installs a `/usr/bin/` binary and nothing else. See
  [`studies/claude-cowork-is-a-desktop-app-not-a-cli.md`](studies/claude-cowork-is-a-desktop-app-not-a-cli.md).
- **Local inference of any kind** — engines, model runners, weight converters. Those load weights,
  which is nixllm's domain by the boundary above, not a matter of taste.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `systemManagerModules`, `lib.catalogue`, `lib.policy`, `checks`. No `nixosModules` — see above. |
| `lib/agents.nix` | The catalogue: one entry per agent CLI, with its pacman name, command, AUR status and the policy `nixpkgs = null`. |
| `modules/nixagent.nix` | Options, catalogue resolution, and the published `archPackages`/`aurPackages`/`binaries`. Also *is* the Arch backend — there is nothing platform-specific left for a second file to hold. |
| `checks/agents-eval.nix` | `nix flake check`: evaluates the module for real via `lib.evalModules` and asserts what it resolves. |
| `experiments/verify-package-names.sh` | Hand-run verification of every name against upstream Arch, the AUR, and the local pacman. |
| `studies/` | Written-up findings that changed a decision here. |

## Platform support

**Arch / CachyOS (via system-manager):** the target. Publishes package-name lists for the host's
own reconciler; installs nothing itself, because on Arch there is no installer here to call.

**NixOS:** deliberately unsupported — see the nixpkgs rule above. A NixOS host that composes this
module gets options it can set and lists nothing reads, which is the honest outcome rather than an
`environment.systemPackages` path that would silently install the frozen copy this repo exists to
refuse.

## Checks

`nix flake check` evaluates `modules/nixagent.nix` against `lib.evalModules` and asserts, among
others: an empty selection resolves to nothing on both lists; every catalogue group has a matching
option and contributes; `archPackages` and `aurPackages` never intersect on *either* distro
setting; every selection lands on exactly one list; every catalogue entry still carries
`nixpkgs = null`; and `claude-code` moves between the lists with `nixagent.distro` and is never on
both.

Each of those was confirmed to actually fail when the invariant is broken — a mislabelled `aur`
flag, an entry naming a nixpkgs attribute, a catalogue group left unwired, and two entries
resolving to the same pacman name each trip their own assertion and nothing else.

## Related projects

Part of the same independently-usable module family:
[nixllm](https://github.com/julian-corbet/nixllm-corbet-ch) (the other side of the wire — serving
models locally, where these only talk to remote ones),
[nixsh](https://github.com/julian-corbet/nixsh-corbet-ch) (the universal terminal-tool catalogue
this repo is deliberately *not* part of), and
[nixarch](https://github.com/julian-corbet/nixarch-corbet-ch) (the Arch package reconciler these
lists are written for).

## License

MIT License &copy; 2026 Julian Corbet
