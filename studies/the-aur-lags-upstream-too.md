# The AUR lags a fast-moving project as badly as nixpkgs does — measured on `omp`

**Finding.** The premise this repo was built on — "nixpkgs pins a release, a distro package does
not" — is only half true. A distro package is still a *human packaging a release*, and for a
project that ships several times a week that human is a lag source of exactly the same kind. On
2026-08-10, upstream `omp` was **17.2.12** while the newer of its two AUR packages sat at
**17.2.3**, ten patch releases behind, with an automated updater account listed as co-maintainer on
both.

**Decided:** a second delivery mode, `homeManagerModules.nixagent`, that runs the vendor's own
installer into the vendor's own per-user prefix. Not a replacement for the pacman/AUR plane — the
consumer chooses per host — and emphatically not a nixpkgs plane, because nixpkgs' problem was
never only staleness.

## The measurement

AUR RPC v5 and each project's own release feed, 2026-08-10:

| Tool | Upstream latest | Distro package | Behind by |
|---|---|---|---|
| `omp` | **17.2.12**, released 2026-08-09 | AUR `oh-my-pi-bin` 17.2.2-1, **flagged out-of-date 2026-08-08**<br>AUR `oh-my-pi` 17.2.3-1, **flagged out-of-date 2026-08-04** | 9–10 patch releases |
| `claude-code` | 2.1.226 | AUR 2.1.220-1, **flagged out-of-date 2026-08-04**<br>`cachyos` repo 2.1.222-1 | 4–6 patch releases |
| `opencode` | 1.18.16, released 2026-08-10 | Arch `extra` 1.18.15-1 | 1 |
| `gemini-cli` | 0.54.4 | Arch `extra` 1:0.50.0-1 | 4 minor releases |
| `codex` | 0.147.0 | Arch `extra` `openai-codex` 0.146.1-1 | 1 minor |

Two things in that table matter more than the raw numbers.

**The lag is not uniform, and it is worst where it hurts most.** `opencode` and `codex` are within
one release; they are in Arch's `extra`, maintained by the distro's own pipeline. `omp` is in the
AUR, maintained by one volunteer, and it is ten releases behind. The AUR is precisely where the
newest and fastest-moving tools live, which is where its single-maintainer model is under the most
pressure.

**Automation did not fix it.** Both `oh-my-pi` packages list `omp-updater` as a co-maintainer — an
account whose name says exactly what it is for. It still fell ten releases behind and both packages
still carry an out-of-date flag. Whatever that bot does, it is not keeping pace with the project,
and no consumer of this catalogue can tell that from the package name.

## Why this is not the same argument as the nixpkgs one

It is worth being precise, because the conclusions differ.

**nixpkgs is refused for a structural reason.** A store path is read-only, so `claude update`,
`omp` self-update and every equivalent cannot run *at all*. The tool freezes until a human bumps a
`flake.lock`, and spends the interval telling its operator to update while being unable to. That
argument does not depend on how fresh nixpkgs is, and a nixpkgs that was perfectly current would
still fail it.

**The AUR is not refused, it is supplemented.** `pacman -Syu` genuinely *is* the updater on an Arch
host, which is the property this repo wanted. The finding above is narrower: that updater can only
deliver what a packager has packaged. On a host that reconciles distro packages anyway, that is
usually fine and the AUR plane stays the right answer. On a host that has no such reconciler, or
for a tool whose packaging has visibly stalled, it is not.

So the two modes answer different questions and neither wins globally:

| | pacman/AUR plane | upstream plane |
|---|---|---|
| Updates via | `pacman -Syu`, with the host's other packages | the tool's own updater |
| Freshness bounded by | a packager | the vendor's own release |
| Needs | a distro package manager and (for AUR) a helper | `curl` and a `$HOME` |
| Works on NixOS | no | yes |
| Reconciles/removes cleanly | yes, pacman owns the files | no, nothing owns the files |

That last row is the honest cost, and it is why this was added as a second mode rather than as a
replacement: nothing on the upstream plane can uninstall anything. Deselecting a tool leaves the
binary exactly where it was. On the pacman plane the reconciler removes it.

## What was rejected

**Pinning a version on the upstream plane.** Every installer accepts one — `claude.ai/install.sh`
takes `stable|latest|VERSION`, `omp.sh/install` takes `--ref`. Using either would reintroduce
precisely the freeze this repo exists to avoid, one layer further out, and would make the
idempotency probe (`is the launcher present?`) wrong, because a present-but-older launcher would
then need replacing. The probe and the no-pinning rule are the same decision.

**Filing the AUR packages as out of date and waiting.** They already are, by someone else, and had
been for two and six days respectively at the time of measurement. That is the mechanism working as
designed; it is just slower than the project.

**Dropping the AUR plane in favour of upstream everywhere.** The distro plane has the property the
upstream plane cannot have: pacman owns the files, so the converge can remove them. On a host that
already reconciles packages, giving that up to chase a version number would be a bad trade.
