#
# The agent catalogue: clients for REMOTE frontier models -- one entry per selectable package,
# naming it on each platform this repo is willing to install from. Two shapes today, `cli` (a
# terminal binary) and `desktop` (an Electron window); THE PLACEMENT RULE below is why both belong
# in the same file despite the different interface.
#
# THE PLACEMENT RULE, stated as a boundary rather than a list, in the same shape nixsh's own
# lib/tools.nix header states its display rule:
#
#   Does the tool drive a remote frontier model it does not host, delivered as a package that
#   self-updates faster than nixpkgs tracks it?
#     yes -> it belongs here, catalogued as `cli` or `desktop` by whichever interface it actually
#            has -- that split is about grouping honestly, not about eligibility
#     no  -> it belongs to whichever repo owns the thing it actually is
#
# Whether the tool opens a terminal or a window is NOT the eligibility test, and it is worth being
# explicit that this file used to apply exactly that clause: `claude-cowork-linux` was checked
# against it and excluded for failing it, see
# ../studies/claude-cowork-is-a-desktop-app-not-a-cli.md. The category a person actually
# maintains is "my AI tooling", and an Electron client sits in it the same way a terminal one does
# -- both carry the identical delivery problem below (AUR-only, self-updating, must never be
# pinned by nixpkgs) regardless of which surface renders the reply. The `.desktop`-entry test from
# that study still correctly separates `cli` from `desktop`; it no longer separates "in this
# catalogue" from "not".
#
# Two neighbours this rule is drawn against, both of which could plausibly have claimed these
# entries, and neither of which should:
#
#   - nixllm SERVES models. Its domain is a broker, an inference engine, a model store, a GPU --
#     software that loads weights and answers requests. Everything catalogued below, `desktop`
#     included, is an HTTPS client that never loads a weight and has no opinion about a GPU. Same
#     project space, opposite side of the wire, so a shared catalogue would mean one repo whose
#     entries need two unrelated kinds of host to be useful.
#   - nixsh is universal BY CONSTRUCTION -- every host has a shell and reaches for a terminal tool,
#     which is exactly why that catalogue has no per-host story to build. These do not have that
#     property and must not inherit it: a small production server has a shell and wants `ripgrep`,
#     and emphatically does not want a self-updating agent client and its Node/Electron runtime --
#     doubly true for `desktop`, which additionally needs a display the server does not have.
#     "Runs in a terminal" is a shape, not a domain; nixsh's claim is the domain "every host needs
#     this", and these fail it regardless of shape.
#
# ── THE RULE THIS REPO EXISTS FOR: NEVER nixpkgs, AND THE REASON IS NOT FRESHNESS ──────────────
#
# Every entry below carries `nixpkgs = null`. That null is a POLICY, not an absence, and the
# distinction matters enough to mechanise: checks/agents-eval.nix asserts it for every entry, so an
# addition that names a real nixpkgs attribute fails `nix flake check` rather than quietly opening
# the door this repo was drawn to keep shut.
#
# nixpkgs really does carry four of the five CLIs. Force-evaluated -- not `hasAttrByPath` alone,
# which cannot tell a live attribute from a rename-to-throw. Re-measured 2026-08-11 against
# nixpkgs-unstable HEAD d482ef84, with each project's own release feed and the Arch package API
# alongside, because the ONLY honest version of this table is one with all three columns:
#
#                     nixpkgs-unstable   Arch/AUR            upstream
#     claude-code     2.1.226            2.1.222 (cachyos)   2.1.226
#     opencode        1.18.13            1.18.16 (extra)     1.18.16
#     codex           0.147.0            0.146.1 (extra)     0.147.0
#     gemini-cli      0.47.0             1:0.50.0 (extra)    0.54.4
#     omp             -- absent --       17.2.2 (AUR, flagged out of date)   17.2.12
#
# READ THAT TABLE HONESTLY: nixpkgs is not uniformly behind. It is AHEAD of Arch for codex and for
# claude-code, level for opencode's packaging lag, and catastrophically behind only for gemini-cli
# -- which nixpkgs is winding down rather than tracking (see that entry). An earlier revision of
# this header claimed "every one of the four is behind the distro package". That was true of the
# snapshot it was taken from (2026-08-03) and is false now. Freshness is a race that changes hands
# week to week, so a rule resting on it would have to be re-argued every week.
#
# THE RULE DOES NOT REST ON IT. It rests on ONE structural property, and this is the whole reason:
#
#     THESE TOOLS SELF-UPDATE, AND A STORE PATH IS READ-ONLY.
#
# Each of them ships its own updater and expects to rewrite its own install on a cadence measured
# in days. `/nix/store` is immutable by construction, so the updater cannot run AT ALL -- not
# slowly, not with a warning: the version freezes until a human bumps a flake.lock, and the tool
# spends the interval telling its operator to update while being structurally unable to. That
# argument does not depend on how fresh nixpkgs is, and a nixpkgs that was perfectly current would
# still fail it. Freshness is the symptom; immutability is the cause.
#
# So there is no `nixpkgs` field to fill in and no `nixosModules` output -- see ../README.md.
#
# ⚠ AND THE BOUNDARY THAT FOLLOWS, because "never nixpkgs" has been over-read as "never nix":
# the prohibition is on nix owning the TOOL. It says nothing about nix supplying the tool's
# RUNTIME or the installer's own dependencies. `programs.nix-ld` providing a loader, and
# `nixagent.home.extraPath` handing the installer a nixpkgs curl and bash, are not exceptions to
# the rule -- they are the rule working. Nix builds the ground the vendor's artifact stands on;
# the artifact stays the vendor's.
#
# ── TWO DELIVERY MODES, BECAUSE THE AUR IS NOT ALWAYS FRESH EITHER ─────────────────────────────
#
# The reasoning above is about nixpkgs, and it holds. What it does NOT establish is that a distro
# package is always current -- and for a fast-moving entry it measurably is not. The `omp` and
# `gemini-cli` rows above are the measurement: an `omp-updater` bot is listed as a co-maintainer on
# both AUR packages and they are ten patch releases behind anyway. That is the same failure mode as
# a stale nixpkgs derivation wearing a different hat. A packager is a human in the loop of a
# project that ships several times a week.
#
# So a SECOND delivery mode exists alongside the distro one: run the VENDOR's own installer into
# the vendor's own per-user prefix, which is what these projects actually support and test, and
# which leaves `<tool> update` working afterwards. The two modes are chosen PER HOST by the
# consumer -- pacman/AUR on an Arch box that already reconciles packages, upstream on a NixOS box
# that has no such reconciler and would otherwise get nothing at all. Neither is forced, and this
# file makes no attempt to rank them: which one is right is a fact about the host.
#
# ── WHAT A HOST WITH NEITHER IS SUPPOSED TO DO ─────────────────────────────────────────────────
#
# A NixOS host has no pacman, so the upstream plane is its ONLY plane here, and an entry whose
# vendor ships no installer is simply absent on it. That is a real limit and it is recorded rather
# than papered over -- `upstream = null` is a finding with a date and a method attached, and
# ../modules/home.nix derives its option type from the entries that have one, so selecting such a
# tool is an eval error instead of an activation that quietly fetches nothing.
#
# It is a limit, NOT a licence to reach for nixpkgs: the structural argument above applies hardest
# to exactly these entries. The catalogued way out is a vendor installer appearing, which is not
# hypothetical -- `openai-codex` sat at `upstream = null` for four days on a measured 403 and now
# carries a live record, because the URL that answered 403 was never the vendor's (see that entry).
# Re-probe before concluding a tool is unreachable; a 403 is a fact about a URL, not about a tool.
#
# The other candidate ways out have been considered and are NOT accepted as an upstream mode:
# `npm install -g` installs into whichever node prefix the host happens to have configured, which
# makes `installs` a property of the host rather than of the tool -- if that is ever wanted, the
# prefix belongs on a module option and the package name in a field of its own, not smuggled into
# this one. Nothing below invents either.
#
# Mechanically the two modes live on different planes: `arch`/`aur`/`archRepoOn` feed
# ../modules/nixagent.nix (system-manager, publishes package-name lists), `upstream` feeds
# ../modules/home.nix (home-manager, runs the installer once per user). NOTHING about the upstream
# mode pins a version -- see ../lib/install-upstream.sh's header for the contract in full.
#
# ── FIELDS ─────────────────────────────────────────────────────────────────────────────────────
#
# `arch`        the pacman package name.
# `binary`      the command it actually installs. NOT always the package name -- `openai-codex`
#               ships `codex`, `claude-code` ships `claude`. Published as `nixagent.binaries` for
#               a consumer writing config or a launcher against these tools, because pointing
#               either at the PACKAGE name is a command that does not exist. Same reasoning as
#               nixmsg's own `binary` field, which exists because "telegram-desktop" launches
#               nothing.
# `aur`         (default false) the name lives in the AUR rather than an official Arch repo. Load-
#               bearing in one direction only, and fatally: `pacman -S` resolves a transaction
#               atomically, so ONE AUR name in a pacman list fails the whole thing with "target not
#               found" and takes every unrelated package in the same converge down with it.
# `archRepoOn`  (default [ ]) Arch DERIVATIVES whose own repositories carry an otherwise-AUR name,
#               so a host on one of them gets the repo build instead of a source build. Consumed
#               against `nixagent.distro` -- see ../modules/nixagent.nix. Exists for exactly one
#               entry today and is documented at that entry.
# `nixpkgs`     always null. See above. The field is present rather than omitted so that a reader
#               cannot mistake the policy for an oversight.
# `upstream`    the vendor's own per-user installer, or null. Present on EVERY entry for the same
#               reason `nixpkgs` is -- checks/agents-eval.nix asserts the field exists, so "this
#               tool has no vendor installer" is a recorded finding rather than a blank. Shape:
#
#                 url       the installer, fetched over HTTPS.
#                 runner    the interpreter to run it with. Not always bash: omp's is `#!/bin/sh`
#                           and POSIX throughout, claude's and opencode's are bash and use bash
#                           features. Recorded per entry rather than assumed, because running a
#                           bash installer under dash fails in ways that look like network faults.
#                 args      flags needed to make the install DETERMINISTIC. Not cosmetic -- see
#                           the omp and opencode entries, where the default invocation either
#                           installs somewhere else entirely or edits the user's shell rc files.
#                 env       (default { }) environment variables exported FOR THE INSTALLER RUN
#                           ONLY, for a vendor whose non-interactive switch is an env var rather
#                           than a flag. Same job as `args` and the same standard of evidence:
#                           nothing goes in here that the vendor does not itself document or use.
#                           Exists for `openai-codex`, whose installer has exactly two flags
#                           (`--release`, `--help`) and gates every prompt on `CODEX_NON_INTERACTIVE`
#                           -- and whose OWN self-updater sets that variable when re-running it.
#                 needs     (default [ ]) commands the installer requires BEYOND the universal
#                           floor (curl, the runner, env), preflighted by name before anything is
#                           fetched. Not a dependency list for a package manager -- this repo
#                           installs nothing -- but the names a consumer's `nixagent.home.extraPath`
#                           has to satisfy on a host with no FHS.
#
#                           IT EXISTS BECAUSE THE FAILURE WITHOUT IT LIES. codex parses release
#                           metadata with a hand-written JSON tokeniser in awk, for both its CDN
#                           path and its GitHub fallback. With no awk on an activation's PATH both
#                           fail in turn and the install dies reporting "Could not parse
#                           releases.openai.com release metadata for Codex latest", plus a broken
#                           pipe from the `fold` feeding it. That names OpenAI's CDN for what is a
#                           missing coreutils-adjacent binary, and sends a reader to the network.
#                           Exactly the class of misdirection the curl and runner preflights above
#                           already exist to prevent; this generalises them per entry.
#
#                           ONLY HARD REQUIREMENTS BELONG HERE. A tool the installer guards with
#                           `command -v` and has a fallback for is NOT a need -- codex probes
#                           shasum/openssl/flock/wget that way and works without every one of them.
#                           Listing those would make a host install packages to satisfy a preflight
#                           for code paths it never takes.
#                 installs  the launcher the installer creates, RELATIVE TO $HOME. This is the
#                           idempotency probe (present -> nothing is fetched), the post-install
#                           verification target, and the directory added to PATH. Its basename is
#                           always the entry's `binary`; checks/agents-eval.nix asserts that.
#                 needsDynamicLoader
#                           whether the artifact that lands requires the FHS dynamic loader at
#                           `/lib64/ld-linux-x86-64.so.2`. That is a HOST REQUIREMENT a
#                           distro-agnostic catalogue cannot assume: NixOS has no FHS and provides
#                           the path only via `programs.nix-ld`, configured rather than merely
#                           enabled. When true, lib/install-upstream.sh preflights the loader and
#                           aborts before downloading, instead of letting the binary fail at exec
#                           with an ENOENT naming a file that is plainly present.
#
#                           A FIELD AND NOT AN UNCONDITIONAL CHECK, because "no loader" is fatal
#                           only to an artifact that wants one. An installer that dropped a shell
#                           script would work perfectly on a host that fails this test, and
#                           refusing it there would be a false negative rather than caution.
#
#                           ⚠ IT IS NOT "IS THIS A NATIVE BINARY", which is what this field was
#                           called until 2026-08-11 and is the reason it is not called that now.
#                           `openai-codex` ships the most native artifact in the catalogue -- a
#                           258 MB Rust executable -- and needs NO loader, because it is a
#                           static-PIE musl build with no PT_INTERP segment at all (verified by
#                           parsing the program headers of the release asset: 9 phdrs, 4x LOAD +
#                           DYNAMIC/TLS/GNU_EH_FRAME/GNU_STACK/GNU_RELRO, no INTERP). Naming the
#                           field after the artifact rather than after the requirement would have
#                           made codex demand nix-ld on hosts that can run it bare -- a false
#                           prerequisite, which is precisely the false negative the paragraph above
#                           says this field exists to avoid.
#
#               The prefix belongs to the INSTALLER, not to this catalogue: `installs` records
#               where each vendor puts things, it does not decide it. They do not agree with each
#               other (opencode uses ~/.opencode/bin, the other two ~/.local/bin), which is why
#               this is a per-entry field and not one module-wide `prefix` option pretending to
#               steer something it cannot.
# `note`        why the entry is what it is, where that is not obvious from the name.
#
# ── THE ATTRIBUTE KEY NAMES THE TOOL, NOT THE PACKAGE ──────────────────────────────────────────
#
# Five of the six keys below happen to equal their `arch` value, which for a long time made the
# key look like "the pacman name". It is not, and `omp` is where that stops being a coincidence:
# its pacman name is `oh-my-pi-bin`, where `-bin` is an AUR packaging convention distinguishing
# one of TWO AUR packages for the same tool, and the key is also what a consumer writes on the
# home-manager plane, where the AUR does not exist and `-bin` would be meaningless. So the key is
# the name the project uses for itself; `arch` and `binary` and `upstream` are what each delivery
# mode calls it. Keys are unique across ALL groups (checks/agents-eval.nix asserts it), because
# ../modules/home.nix flattens the groups into one selection space.
#
# ── VERIFIED, NOT GUESSED ──────────────────────────────────────────────────────────────────────
#
# Every `arch` name below was checked on 2026-08-07 against THREE independent sources, because two
# of them disagree for one entry and only the third resolves it:
#
#   - `pacman -Si <name>` on a live CachyOS system, which reports the repository a name resolves in.
#   - archlinux.org's own package search API (`/packages/search/json/?name=<name>`), which is
#     upstream Arch and knows nothing about a derivative's extra repositories.
#   - the AUR RPC (`https://aur.archlinux.org/rpc/v5/info?arg[]=<name>`).
#
# A `pacman -Si` hit alone is NOT sufficient evidence for `aur = false`, and this catalogue is the
# proof: `claude-code` resolves cleanly in `pacman -Si` on a CachyOS box and is in no upstream Arch
# repository at all. Trusting the first source alone would have written `aur = false` and handed
# every plain-Arch consumer the whole-transaction abort described above.
#
# ── CONSIDERED AND EXCLUDED ────────────────────────────────────────────────────────────────────
#
# Named here rather than silently left out, so the boundary is decidable for the next candidate
# instead of re-argued:
#
#   - local inference runners of every kind (an engine, a model-serving GUI, a weights converter).
#     Those load weights, which is nixllm's domain by the boundary above, not a matter of taste.
{ ... }:
{
  # ── Agentic CLIs: an interactive terminal agent driving a remote frontier model ──────────────
  cli = {
    claude-code = {
      arch = "claude-code";
      binary = "claude";
      nixpkgs = null;

      # THE ONE ENTRY THAT IS NOT THE SAME ANSWER ON EVERY ARCH-FAMILY HOST, and the reason
      # `archRepoOn` exists at all. Checked three ways on 2026-08-07:
      #
      #   archlinux.org package search  -> 0 results. Upstream Arch does not package it, in any
      #                                    repository, on any architecture.
      #   AUR RPC                       -> present, PackageBase `claude-code`, maintained, ~87
      #                                    votes. This is where a plain Arch host gets it.
      #   `pacman -Si claude-code`      -> found, `Repository: cachyos`. Note the repository name:
      #                                    CachyOS's OWN repo, not one of its `*-v3` rebuilds of an
      #                                    Arch repo, so this is a package that exists because that
      #                                    derivative chose to ship it.
      #
      # Hence `aur = true` as the FLOOR -- correct for upstream Arch, and the direction that cannot
      # abort a transaction -- with `archRepoOn` lifting it to the pacman list only on a distro
      # whose own repository is known to carry it. A host that declares nothing gets the safe
      # answer; see `nixagent.distro` in ../modules/nixagent.nix.
      aur = true;
      archRepoOn = [ "cachyos" ];

      # Anthropic's own installer, and the entry the upstream mode was built against because it was
      # already in use by hand on a host here: `~/.local/bin/claude` pointing into
      # `~/.local/share/claude/versions/<version>`, which is this installer's layout.
      #
      # `installs` is NOT readable out of install.sh, and that is worth stating rather than
      # implying. The script (read 2026-08-10) only downloads a versioned binary into
      # `~/.claude/downloads`, checksums it against the release manifest, runs `<binary> install`,
      # and deletes the download. The launcher path is decided inside that `install` subcommand,
      # so the value below is taken from a live host where this installer was used, not from the
      # script -- and the post-install verification in ../lib/install-upstream.sh is what turns a
      # wrong guess into a loud failure instead of a silent one.
      #
      # No args: the script takes an optional `stable|latest|VERSION` target and defaults to
      # latest, which is exactly what is wanted -- pinning a version here would reintroduce the
      # problem this repo exists to avoid. It also refuses to run under sudo (it would install
      # into root's home), which suits a home-manager activation exactly.
      upstream = {
        url = "https://claude.ai/install.sh";
        runner = "bash";
        args = [ ];
        installs = ".local/bin/claude";
        # linux-x64 artifact: `Elf file type is EXEC`, `INTERP /lib64/ld-linux-x86-64.so.2`.
        # Its musl fallback is unreachable on NixOS -- the detection is
        # `[ -f /lib/libc.musl-*.so.1 ] || ldd /bin/ls | grep -q musl`, and NixOS has no /bin/ls,
        # so it selects the glibc build on exactly the hosts that cannot run it unaided.
        needsDynamicLoader = true;
      };

      note = ''
        Anthropic's agentic coding CLI (github.com/anthropics/claude-code). Package `claude-code`,
        command `claude`.
      '';
    };

    gemini-cli = {
      arch = "gemini-cli";
      binary = "gemini";
      nixpkgs = null;

      # NO VENDOR INSTALLER, and RE-PROBED 2026-08-11 rather than left on the earlier note --
      # because the sibling entry below shows what a stale probe costs. Every candidate answers 404
      # (raw .../main/install.sh, .../master/install.sh, .../main/scripts/install.sh), gemini-cli.dev
      # does not resolve, and storage.googleapis.com/gemini-cli/install.sh answers 403. The README
      # documents npx, `npm install -g`, Homebrew, MacPorts and conda -- no shell installer.
      #
      # AND NO BINARY TO PLACE EITHER, which the earlier note got wrong by inference. The last 15
      # releases (stable, preview and nightly alike) carry an IDENTICAL three-asset set:
      # gemini-cli-bundle.zip plus two darwin zips. There is no Linux artifact at all, and the
      # bundle is not one -- `gemini.js` opens `#!/usr/bin/env node`. The project's own
      # scripts/build_binary.js has a working linux branch; Google simply does not publish its
      # output. So this is npm/Node-only on Linux, not "binaries with no script to place them".
      #
      # `npm install -g` is deliberately NOT accepted as an upstream mode here. It installs into
      # whichever node prefix happens to be configured -- a nix-store node's prefix is read-only,
      # a system node's is root-owned -- so the destination this catalogue would have to record as
      # `installs` is a property of the host's node setup rather than of the tool. That is exactly
      # the ambiguity the probe path exists to remove. It is not unfixable, and the header says
      # where the fix would have to live (a module option for the prefix, a field for the package
      # name); it is not built because nothing has asked for it and this entry may not be the one
      # to ask -- see the retirement note below.
      upstream = null;

      note = ''
        Google's terminal agent for Gemini (github.com/google-gemini/gemini-cli). Package
        `gemini-cli`, command `gemini`. Official upstream Arch `extra` (archlinux.org search:
        `extra`, x86_64, 2026-08-07), so no AUR helper is needed for it anywhere.

        Distro-plane only: with no vendor installer, a host that cannot use pacman gets nothing
        for this entry, and says so at eval time rather than at runtime -- `nixagent.home.upstream`
        is typed to the entries that HAVE an installer, so naming this one there is a type error.

        ⚠ THE VENDOR IS RETIRING IT, which is context this catalogue should carry before anyone
        spends effort widening a plane to reach it. Google announced Gemini CLI's replacement by
        Antigravity CLI, and nixpkgs marked the package accordingly on 2026-08-07:
        `meta.problems.removal.message` reads "Unpaid tier and Google AI Pro/Ultra users: Gemini
        CLI was replaced by Antigravity CLI." That also explains the freshest measurement in this
        file's header -- nixpkgs has not bumped this package since 2026-06-22 and is 8 stable
        releases behind, which is a wind-down rather than a packaging lag. `antigravity-cli` is
        already in nixpkgs (1.1.11, a fetched-binary package). Whether this catalogue follows the
        vendor there is a decision for a consumer, not something to infer here.
      '';
    };

    openai-codex = {
      arch = "openai-codex";
      binary = "codex";
      nixpkgs = null;

      # ⚠ THIS ENTRY READ `upstream = null` FROM 2026-08-07 TO 2026-08-11, AND THAT WAS WRONG.
      # The recorded finding was "openai.com/codex/install.sh answers 403". The URL answers 403
      # because it was never OpenAI's -- the installer is served from a different host entirely,
      # and the project README has documented it the whole time:
      #
      #     curl -fsSL https://chatgpt.com/codex/install.sh | sh        -> HTTP 200, 30285 bytes
      #
      # A 403 is a fact about a URL, not about a tool, and treating one as the other kept this tool
      # off every NixOS host for four days. The lesson is in the header: re-probe before concluding
      # a vendor ships nothing, and probe what the vendor DOCUMENTS rather than what a naming
      # convention suggests.
      #
      # `sh`, not bash: the script opens `#!/bin/sh` and is POSIX throughout.
      #
      # NO `args`, because there are only two (`--release VERSION`, `--help`) and neither is
      # wanted -- pinning a release here would reintroduce exactly what this plane avoids. The two
      # non-default behaviours this install DOES need steering are handled the only ways the vendor
      # offers, and both are load-bearing:
      #
      #   1. `env.CODEX_NON_INTERACTIVE = "1"`. The installer ends in `maybe_launch_codex_now`,
      #      which calls `prompt_yes_no "Start Codex now?"`. That helper returns early only for
      #      this variable; otherwise it tests `( : </dev/tty )` FIRST, before `[ -t 0 ]`. An
      #      activation run from a systemd unit has no tty and would fall through harmlessly -- but
      #      a `home-manager switch` typed at a terminal HAS one, so the switch would stop at an
      #      interactive prompt and, if answered, launch a TUI from inside an activation script.
      #      Not a guess at a magic variable either: codex's own updater re-runs this installer as
      #      `curl -fsSL <url> | CODEX_NON_INTERACTIVE=1 sh` (codex-rs/tui/src/update_action.rs).
      #   2. The PATH prepend in ../lib/install-upstream.sh. This installer has NO
      #      `--no-modify-path` equivalent: its `add_to_path` returns early ONLY when `$BIN_DIR` is
      #      already in `$PATH`, and otherwise writes a `# >>> Codex installer >>>` block into a
      #      shell rc chosen by `pick_profile` (~/.bashrc, ~/.zshrc, or ~/.profile for any other
      #      shell -- fish lands in the last). An activation inherits no login PATH, so without the
      #      prepend this installer edits a file nix believes it owns, on every fresh install.
      upstream = {
        url = "https://chatgpt.com/codex/install.sh";
        runner = "sh";
        args = [ ];
        env = { CODEX_NON_INTERACTIVE = "1"; };

        # Measured on the first real switch that selected this entry (2026-08-11), not predicted:
        # the install failed with "Could not parse releases.openai.com release metadata for Codex
        # latest" on a host whose PATH had curl, bash, coreutils, tar, gzip, unzip, grep and sed --
        # everything the other three installers need, and no awk. `parse_release_metadata` is
        # `LC_ALL=C fold -b -w 4096 | LC_ALL=C awk '<a JSON tokeniser>'`, and the GitHub fallback
        # parses the same way, so both sources "fail" identically and the diagnostic names the CDN.
        #
        # awk ONLY. sha256sum comes from coreutils and is codex's first choice; shasum, openssl,
        # flock, lockf and wget are all `command -v`-guarded with working fallbacks.
        needs = [ "awk" ];

        installs = ".local/bin/codex";

        # FALSE, and it is the entry that made the field's name a bug worth fixing -- see the
        # `needsDynamicLoader` documentation in the FIELDS section above. Every Linux artifact in
        # the release is `-unknown-linux-musl`; there is no `-linux-gnu` build of the CLI at all.
        # Program headers parsed off the actual asset: ET_DYN, 9 phdrs, 4x LOAD + DYNAMIC + TLS +
        # GNU_EH_FRAME + GNU_STACK + GNU_RELRO. No INTERP segment, so it is a static PIE and starts
        # on a host with no FHS and no nix-ld whatsoever.
        needsDynamicLoader = false;
      };

      note = ''
        OpenAI's terminal coding agent (github.com/openai/codex). Official upstream Arch `extra`
        (verified 2026-08-07).

        THE PACKAGE AND THE COMMAND DISAGREE, in both directions from the upstream project name:
        the pacman package is `openai-codex` (the bare `codex` is taken on Arch), the command it
        installs is `codex`, and the project repository is `openai/codex`. A caller that guesses
        either name from the other is wrong half the time -- which is what `binary` is for.

        The installer places versioned release directories under `~/.codex/packages/standalone` and
        points `~/.local/bin/codex` at the current one, so `codex update` keeps working afterwards
        -- which is the post-condition this whole plane exists for. Where a store path WOULD have
        broken it is worth recording precisely, because codex fails softly rather than loudly:
        `install-context` classifies an unrecognised exe path as `InstallMethod::Other`, which maps
        to no update action, so the TUI silently stops offering updates and `codex update` exits
        with "Could not detect the Codex installation method". Frozen, with no error to search for.
      '';
    };

    opencode = {
      arch = "opencode";
      binary = "opencode";
      nixpkgs = null;

      # The one catalogued installer that does NOT use ~/.local/bin, and the reason `installs` is
      # a per-entry field instead of one module-wide prefix option. Read out of the script itself
      # (2026-08-10, line 68): `INSTALL_DIR=$HOME/.opencode/bin`, hard-coded, honouring no env
      # var, followed by `mv`/`chmod 755` of the downloaded binary into it.
      #
      # `--no-modify-path` IS REQUIRED, not tidiness. Without it the installer walks
      # `$HOME/.bashrc $HOME/.bash_profile $XDG_CONFIG_HOME/bash/*` (or the zsh/fish equivalents),
      # picks the first that exists, and appends a PATH export to it. On a home-manager-managed
      # home those files are generated, so the edit is either lost on the next switch or fights
      # it -- and the PATH entry is this module's job anyway (`nixagent.home.addToPath` publishes
      # it through home.sessionPath, declaratively, where it survives).
      upstream = {
        url = "https://opencode.ai/install";
        runner = "bash";
        args = [ "--no-modify-path" ];
        installs = ".opencode/bin/opencode";
        # A glibc binary, and the one whose installer verifies NOTHING after unpacking -- no smoke
        # test at all -- so a host without a loader gets a broken executable and no complaint from
        # the vendor script. The loader preflight is what turns that into a legible failure.
        needsDynamicLoader = true;
      };

      note = ''
        Open-source terminal coding agent (github.com/anomalyco/opencode), model-agnostic: it
        talks to whichever provider it is configured for rather than one vendor's endpoint. Still
        a client by the placement rule -- being able to point it at a locally-served model does not
        make it an inference engine, exactly as a browser is not a web server.

        Official upstream Arch `extra` (verified 2026-08-07). Package name, command name and
        project name all agree, which is worth noting only because three of the four entries here
        do not.
      '';
    };

    omp = {
      # THREE NAMES FOR ONE TOOL, all different, which makes this the sharpest example of the
      # trap `binary` exists for -- worse than `openai-codex`, which only has two:
      #
      #   catalogue key   `omp`                          what the project calls itself
      #   pacman          `oh-my-pi-bin`                 the AUR package
      #   npm             `@oh-my-pi/pi-coding-agent`    what the source install pulls
      #   command         `omp`
      #
      # The npm name is recorded here rather than in a field because nothing in this repo installs
      # from npm -- it is the payload of the vendor installer's OWN source branch, and it is
      # written down because a reader searching for "oh-my-pi" in a lockfile or a bun global
      # directory will find that string and nothing else.
      arch = "oh-my-pi-bin";
      binary = "omp";

      # `nixpkgs = null` here is the policy as everywhere, but note that it is also the FACT for
      # once. Force-evaluated against the pinned revision on 2026-08-10: no `omp`, no `oh-my-pi`.
      # There IS a `pkgs.pi-coding-agent` and it is a trap -- version 0.83.0, homepage pi.dev,
      # mainProgram `pi`. That is Mario Zechner's pi-mono, the project omp FORKED FROM, not omp.
      # A reader pattern-matching on the npm name `@oh-my-pi/pi-coding-agent` would install a
      # different agent under a different command and think the catalogue was being precious.
      nixpkgs = null;

      # AUR-ONLY, AND THE FIRST ENTRY WHERE THE AUR IS ITSELF THE STALE COPY. All three names
      # checked 2026-08-10 against the same three sources this file's header requires:
      #
      #   archlinux.org package search  -> 0 results for `oh-my-pi-bin`, `oh-my-pi` AND `omp`.
      #                                    Upstream Arch packages none of them.
      #   AUR RPC                       -> both present, both flagged out of date (below).
      #   `pacman -Si`                  -> not found on a CachyOS host for any of the three, so
      #                                    unlike `claude-code` there is no derivative repository
      #                                    to lift it to the pacman list. `aur = true` is the
      #                                    whole answer and there is no `archRepoOn`.
      aur = true;

      # WHICH OF THE TWO AUR PACKAGES: `oh-my-pi-bin`, the prebuilt release binary. They conflict
      # with each other (`oh-my-pi-bin` declares Provides+Conflicts on `oh-my-pi`), so this is a
      # real choice, and the source package loses it on build cost rather than on principle. AUR
      # RPC, 2026-08-10:
      #
      #   oh-my-pi-bin  17.2.2-1  depends: glibc
      #                           makedepends: none      6 votes,  popularity 2.63
      #                           flagged out-of-date 2026-08-08
      #   oh-my-pi      17.2.3-1  depends: glibc opus pcre2
      #                           makedepends: bazel bun git   2 votes, popularity 0.84
      #                           flagged out-of-date 2026-08-04
      #
      # `oh-my-pi` builds the project's ~55k-line Rust engine plus its Bun/TypeScript frontend
      # from source, under bazel, on every version bump -- of a project that ships several
      # releases a week, on hosts whose package converge is meant to be unattended. That is a
      # long build repeated constantly for a binary upstream already publishes. It is also the
      # heavier dependency set for the same result.
      #
      # Note what the two versions say together, because it is the whole argument for the second
      # delivery mode: upstream was 17.2.12 (released 2026-08-09) while the newest of the two AUR
      # packages sat at 17.2.3, and BOTH list an `omp-updater` bot as co-maintainer. Automation in
      # the packaging loop did not keep them within ten patch releases of upstream. A host that
      # wants this tool current uses `nixagent.home.upstream`, not the AUR.
      upstream = {
        url = "https://omp.sh/install";
        runner = "sh";

        # `--binary` IS LOAD-BEARING, and this is the finding that made `args` a field. The
        # installer's DEFAULT branch is not deterministic about WHERE it installs (script read
        # 2026-08-10):
        #
        #   bun on PATH, matching arch  -> `bun install -g @oh-my-pi/pi-coding-agent`, which lands
        #                                  in bun's own global prefix ($BUN_INSTALL/bin, i.e.
        #                                  ~/.bun/bin/omp by default)
        #   otherwise                   -> downloads omp-linux-<arch> to
        #                                  "${PI_INSTALL_DIR:-$HOME/.local/bin}/omp"
        #
        # So the destination depends on whether some unrelated tool happens to be installed on the
        # machine, and `installs` -- the idempotency probe -- would be right on one host and wrong
        # on the next, where it would reinstall on every single activation while reporting
        # success. `--binary` forces the second branch, which is the one whose destination this
        # catalogue can actually state. It also skips installing bun as a side effect, which a
        # module that claims to install `omp` has no business doing.
        args = [ "--binary" ];

        installs = ".local/bin/omp";
        # omp-linux-x64: `INTERP /lib64/ld-linux-x86-64.so.2`, same as claude's. Its installer DOES
        # smoke-test, and on failure exits 1 while LEAVING the broken binary in place -- the state
        # lib/install-upstream.sh now clears rather than inheriting on the next activation.
        needsDynamicLoader = true;
      };

      note = ''
        Oh My Pi (github.com/can1357/oh-my-pi, omp.sh) by can1357 -- a terminal AI coding agent
        with a native Rust engine and a Bun/TypeScript frontend, forked from Mario Zechner's
        pi-mono. Command `omp`; AUR package `oh-my-pi-bin`; npm package
        `@oh-my-pi/pi-coding-agent`. Three names, no two of them the same.

        A client by the placement rule, same as `opencode`: it drives whichever remote provider it
        is configured for and loads no weights of its own.
      '';
    };
  };

  # ── Desktop AI clients: an Electron window driving a remote frontier model ────────────────────
  #
  # Same delivery problem as `cli` above -- AUR-only, self-updating, must never be pinned by
  # nixpkgs -- despite drawing a window instead of running in a terminal. Kept as its OWN group
  # rather than folded into `cli` so that group's documented meaning ("terminal clients driving a
  # remote frontier model") stays true rather than being quietly stretched to also cover an
  # Electron app with a `.desktop` entry. See ../studies/claude-cowork-is-a-desktop-app-not-a-cli.md
  # for the evidence that it genuinely is a window, and this file's own header for why that no
  # longer excludes it from the catalogue -- only from the `cli` group within it.
  desktop = {
    claude-cowork-linux = {
      arch = "claude-cowork-linux";
      binary = "claude-cowork";
      nixpkgs = null;

      # AUR-only, and unlike `claude-code` there is no repository lift: no Arch derivative's own
      # repository carries this one, so `archRepoOn` is omitted rather than set to `[ ]` -- the
      # field's own documentation says it appears only on an entry that needs it, and
      # checks/agents-eval.nix asserts exactly that. Checked three ways on 2026-08-07, the same
      # three sources this file's header describes:
      #
      #   archlinux.org package search      -> 0 results. Upstream Arch does not package it, in
      #                                         any repository, on any architecture.
      #   AUR RPC                           -> present, PackageBase `claude-cowork-linux`,
      #                                         1.1.4010-10, maintainer `johnzfitch`, 3 votes.
      #   `pacman -Si claude-cowork-linux`  -> "error: package 'claude-cowork-linux' was not
      #                                         found" on the host this was checked from -- no
      #                                         derivative repository resolves it, so `aur = true`
      #                                         is not merely the floor here, it is the whole
      #                                         answer, with nothing for `archRepoOn` to lift.
      aur = true;

      # NO VENDOR INSTALLER, and structurally so rather than by omission: the AUR package is a
      # THIRD PARTY's repackaging of a proprietary Electron application (license
      # `custom:proprietary`, upstream a repackaging repository rather than an Anthropic-published
      # one -- see ../studies/claude-cowork-is-a-desktop-app-not-a-cli.md). There is no vendor
      # per-user install script to run, so the upstream plane cannot serve this entry at all and
      # a NixOS host simply does not get it. Stated, not papered over.
      upstream = null;

      note = ''
        Anthropic's Claude Desktop with Cowork (local agent) support (AUR: johnzfitch/
        claude-cowork-linux). Package `claude-cowork-linux`, command `claude-cowork` -- the two
        disagree, same trap `openai-codex` documents above.

        An Electron application: it installs a `.desktop` entry (`Type=Application`,
        `StartupWMClass=Claude`, no `Terminal=true`), which is why it is a `desktop` selection
        rather than a `cli` one and not, by itself, a reason to leave it out of this catalogue --
        see the header. The Cowork feature drives Anthropic's remote model, same as `claude-code`;
        nothing here loads a weight locally.
      '';
    };
  };
}
