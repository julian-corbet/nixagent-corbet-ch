# studies

Written-up findings: things that were checked in [`../experiments/`](../experiments/README.md),
turned out to matter, and are worth recording properly — with the reasoning, not just the result.

A study earns its place here once it changed a decision in the main project. See the main
[README](../README.md) for the project itself.

| File | Finding |
|---|---|
| `claude-code-is-not-in-arch-official-repos.md` | `claude-code` resolves cleanly under `pacman -Si` on a CachyOS system and is in **no** upstream Arch repository (archlinux.org package search: 0 results); the AUR is where a plain Arch host gets it. `pacman -Si` alone is therefore not sufficient evidence for `aur = false`, because it cannot distinguish a derivative's *own* repository from its rebuild of an Arch one. Decided the entry to carry `aur = true` as the floor plus `archRepoOn = [ "cachyos" ]`, and introduced `nixagent.distro` to resolve between them. |
| `claude-cowork-is-a-desktop-app-not-a-cli.md` | `claude-cowork-linux` (AUR) is an Electron packaging of Claude **Desktop** — it depends on `electron` and installs a `.desktop` entry with `Type=Application` / `StartupWMClass=Claude` and no `Terminal=true`, where every catalogued entry installs a `/usr/bin/` binary and nothing else. Decided to exclude it, and adopted "does it install a `.desktop` entry?" as the catalogue's mechanical placement test. |
