# `claude-cowork-linux` is a desktop application, not a terminal client — excluded

**Finding.** `claude-cowork-linux` (AUR) is an Electron packaging of Anthropic's Claude **Desktop**
with local-agent support. It is a window, not a terminal client, and it does not belong in this
catalogue.

**Decided:** not catalogued. Named in `lib/agents.nix`'s "considered and excluded" header rather
than silently left out, so the boundary is decidable for the next candidate instead of re-argued.

## Why it was a plausible candidate

It is an Anthropic client, it drives a remote frontier model, it self-updates, it is AUR-only, and
it is named for an agentic feature. Every property this repo exists for is present except the one
that decides placement.

## What was checked

Verified 2026-08-07 against the AUR RPC and the built package's own file list.

**AUR metadata** (`aur.archlinux.org/rpc/v5/info?arg[]=claude-cowork-linux`):

| Field | Value |
|---|---|
| Description | Anthropic Claude Desktop with Cowork (local agent) support for Linux |
| `Depends` | `electron`, `nodejs` |
| Upstream | a third-party repackaging repository, not an Anthropic-published one |
| License | `custom:proprietary` |

**The decisive evidence — the package's own file list.** Every entry catalogued in
`lib/agents.nix` installs a `/usr/bin/` binary and *nothing else*. This one also installs a
`.desktop` entry:

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
what it is.

## The rule this settles

`lib/agents.nix`'s placement rule asks whether a tool drives a model it does not host, from a
terminal, **with no window of its own**. `claude-cowork-linux` fails the third clause: its default
and only mode is a window.

That gives the catalogue a mechanical test rather than a judgement call, and it is worth stating
because the next candidate will be argued the same way:

> Does the package install a `.desktop` entry? If yes, it is a desktop application and belongs to
> whichever repo owns desktop applications — not here.

The test survives the obvious objection. "It contains an agent" is a capability, not a shape; a
terminal emulator contains a shell and is still a desktop application. This family's sibling repos
already draw the same line in the opposite direction (a display-default tool belongs to a
display-substrate repo even when it *can* be coaxed into a terminal), so applying it here keeps one
rule rather than two.

## What that means in practice

Nothing about this package becomes undeclarable — it simply belongs to whatever module owns
GUI/desktop applications on the host, alongside every other Electron app, where it will sit next to
things that need a session, a compositor and an icon. It does not belong next to four binaries that
run over SSH on a machine with no display at all.
