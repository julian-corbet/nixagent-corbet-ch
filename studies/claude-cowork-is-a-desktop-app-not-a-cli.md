# `claude-cowork-linux` is a desktop application, not a terminal client — catalogued as `desktop`

**Finding.** `claude-cowork-linux` (AUR) is an Electron packaging of Anthropic's Claude **Desktop**
with local-agent support. It is a window, not a terminal client, and that fact is what separates it
from every `cli` entry in this catalogue.

**Decided:** catalogued, in its own `desktop` group rather than `cli`. Named here so the boundary
between the two groups — and the reason a window is not a reason to leave a tool out of this repo
altogether — is decidable for the next candidate instead of re-argued. See `lib/agents.nix`'s own
header for the placement rule this settles, and `../README.md`'s "Why these are not nixllm's, and
not nixsh's" section for the two boundaries that still exclude other things.

## Why it is a plausible candidate

It is an Anthropic client, it drives a remote frontier model, it self-updates, it is AUR-only, and
it is named for an agentic feature. Every property this repo exists for is present.

## What was checked

Verified 2026-08-07 against the AUR RPC, the built package's own file list, and (re-verified the
same day, for the group split) `pacman -Si` and archlinux.org's package search.

**AUR metadata** (`aur.archlinux.org/rpc/v5/info?arg[]=claude-cowork-linux`):

| Field | Value |
|---|---|
| Description | Anthropic Claude Desktop with Cowork (local agent) support for Linux |
| `Depends` | `electron`, `nodejs` |
| Upstream | a third-party repackaging repository, not an Anthropic-published one |
| License | `custom:proprietary` |
| Maintainer | `johnzfitch`, 3 votes, version `1.1.4010-10` |

**The package's own file list.** Every `cli` entry in `lib/agents.nix` installs a `/usr/bin/` binary
and *nothing else*. This one also installs a `.desktop` entry:

```
/usr/bin/claude-cowork
/usr/share/applications/claude-cowork.desktop
```

```ini
[Desktop Entry]
Name=Claude Cowork
Type=Application
Exec=claude-cowork %U
Icon=claude-cowork
Categories=Development;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
```

`Type=Application` with a `StartupWMClass` and no `Terminal=true` is a launcher for a window with a
toplevel surface. That is not a marginal signal — it is the app telling the desktop environment
what it is. `claude-cowork-linux` genuinely is a desktop application; nothing about that finding is
in question.

**Repository membership**, the same three sources `lib/agents.nix`'s header requires for every
entry:

| Source | Result |
|---|---|
| `pacman -Si claude-cowork-linux` | `error: package 'claude-cowork-linux' was not found` |
| archlinux.org package search | 0 results — no upstream Arch repository carries it |
| AUR RPC | present, `PackageBase claude-cowork-linux`, maintained |

Unlike `claude-code`, no Arch derivative's own repository carries this name — `pacman -Si` returns
nothing on a CachyOS host either. So `aur = true` is not merely the floor here, as it is for
`claude-code`: it is the whole answer, and the catalogue entry carries no `archRepoOn`.

## What the finding does and does not decide

The `.desktop` entry is real, mechanical evidence about the tool's *interface* — this is a window,
not a terminal client, full stop. What it does not settle on its own is *eligibility for this
catalogue*, and that is the part of the original write-up that did not hold up: interface was being
used as the placement test, and the placement test has changed.

The category a person actually maintains is "my AI tooling", not "my terminal AI tooling" — an
Electron client sits in it the same way a CLI does. And the delivery problem that gives this repo
its reason to exist — AUR-only, self-updating on a cadence nixpkgs cannot track, must never be
frozen by a store path — is identical for `claude-cowork-linux` and every `cli` sibling around it,
regardless of which surface renders the reply. Nothing about the window changes any of that.

So the finding stands and now drives a *different* decision: it is exactly why this entry lives in
its own `desktop` group rather than being folded into `cli`. Stretching `cli`'s documented meaning
("terminal clients driving a remote frontier model") to quietly also cover an Electron app would
make that group's own header a lie the next reader has to discover by inspection. A separate group
says the true thing once, at the point where it is decided, instead of leaving a name that
contradicts its own catalogue.

## The mechanical test this leaves behind

> Does the package install a `.desktop` entry? If yes, it is a `desktop` selection. If no, it is a
> `cli` selection.

That test still does real work — it is exactly how `claude-cowork-linux` was told apart from the
four `cli` entries above it — it has simply moved from deciding "in this catalogue or not" to
deciding "which group within it."
