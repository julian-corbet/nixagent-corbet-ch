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
# ── THE RULE THIS REPO EXISTS FOR: pacman/AUR ALWAYS, nixpkgs NEVER ────────────────────────────
#
# Every entry below carries `nixpkgs = null`. That null is a POLICY, not an absence, and the
# distinction matters enough to mechanise: checks/agents-eval.nix asserts it for every entry, so an
# addition that names a real nixpkgs attribute fails `nix flake check` rather than quietly opening
# the door this repo was drawn to keep shut.
#
# nixpkgs really does carry all four. Force-evaluated against a pinned revision on 2026-08-07 --
# not `hasAttrByPath` alone, which cannot tell a live attribute from a rename-to-throw:
#
#   pkgs.claude-code  2.1.220   (pacman: 2.1.222-1)
#   pkgs.gemini-cli   0.47.0    (pacman: 0.50.0-1)
#   pkgs.codex        0.146.0   (pacman: openai-codex 0.146.1-1)
#   pkgs.opencode     1.18.11   (pacman: 1.18.14-1)
#
# So the reason is not availability. It is two measured properties of this class of tool:
#
#   1. THEY SELF-UPDATE. Each of these ships its own updater and expects to rewrite its own install
#      on a release cadence measured in days. A nix-store path is read-only, so the updater cannot
#      run at all -- the version freezes until a human bumps a flake.lock by hand, and the tool
#      spends the interval telling its operator to update while being structurally unable to.
#      A distro package is mutable enough that `pacman -Syu` is the updater, which is the outcome
#      wanted.
#   2. NIXPKGS LAGS, and the table above is the measurement, not an impression -- every one of the
#      four is behind the distro package, one of them by three minor releases. That is nobody's
#      fault: a nixpkgs derivation pins and hashes a release, and these projects release faster
#      than that pipeline settles.
#
# Both point the same way, so this repo does not offer the choice. There is no `nixosModules`
# output and no `nixpkgs` field to fill in -- see ../README.md's own section, and ../modules/
# nixagent.nix's header for what a NixOS host gets instead (nothing, deliberately and loudly).
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
# `note`        why the entry is what it is, where that is not obvious from the name.
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

      note = ''
        Anthropic's agentic coding CLI (github.com/anthropics/claude-code). Package `claude-code`,
        command `claude`.
      '';
    };

    gemini-cli = {
      arch = "gemini-cli";
      binary = "gemini";
      nixpkgs = null;
      note = ''
        Google's terminal agent for Gemini (github.com/google-gemini/gemini-cli). Package
        `gemini-cli`, command `gemini`. Official upstream Arch `extra` (archlinux.org search:
        `extra`, x86_64, 2026-08-07), so no AUR helper is needed for it anywhere.
      '';
    };

    openai-codex = {
      arch = "openai-codex";
      binary = "codex";
      nixpkgs = null;
      note = ''
        OpenAI's terminal coding agent (github.com/openai/codex). Official upstream Arch `extra`
        (verified 2026-08-07).

        THE PACKAGE AND THE COMMAND DISAGREE, in both directions from the upstream project name:
        the pacman package is `openai-codex` (the bare `codex` is taken on Arch), the command it
        installs is `codex`, and the project repository is `openai/codex`. A caller that guesses
        either name from the other is wrong half the time -- which is what `binary` is for.
      '';
    };

    opencode = {
      arch = "opencode";
      binary = "opencode";
      nixpkgs = null;
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
