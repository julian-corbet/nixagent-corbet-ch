# Evaluates ../modules/home.nix -- the UPSTREAM delivery plane -- against `lib.evalModules` with a
# stub of the handful of home-manager options it writes to. Same technique nixmsg's own
# checks/default.nix uses for its home module, and for the same reason: home-manager's option tree
# is a different evaluation from NixOS/system-manager's, `nix flake check` evaluates neither on its
# own, and pulling home-manager in as a flake input to test three option assignments would put a
# second nixpkgs in the closure of a repo that deliberately has none.
#
# WHAT THIS FILE PROVES: that a selection renders the RIGHT CALL -- the right probe path, the right
# installer URL, the right per-entry flags, the dry-run hook, the failure mode, one call per
# selection -- and that the module contributes nothing else. What it deliberately does NOT prove is
# that the rendered script then behaves: idempotency, failure surfacing and the exit-0-installed-
# nothing case are executed for real in ./upstream-install.nix, because those are properties of a
# running shell and no amount of string matching substitutes for running it.
#
# THE STUB IS THE REASON ../modules/home.nix WRITES A LITERAL DAG RECORD instead of calling
# `lib.hm.dag.entryAfter`. `lib.hm` exists only inside a real home-manager evaluation; a module
# that reached for it could not be evaluated here at all, and this whole plane would ship with no
# eval-time cover. The record `{ data; before; after; }` is exactly what that helper returns.
{ pkgs, lib ? pkgs.lib }:
let
  cat = import ../lib/agents.nix { };

  # Only what modules/home.nix actually assigns, plus `home.homeDirectory` which it reads.
  # `home.packages` is stubbed although the module never writes it -- that ABSENCE is one of the
  # assertions below, and an option that does not exist cannot be asserted to be empty.
  homeSurfaceStub = { lib, ... }: {
    options.home = {
      homeDirectory = lib.mkOption { type = lib.types.str; default = "/home/tester"; };
      activation = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; };
      sessionPath = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
      packages = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      file = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; };
    };
  };

  evalWith = selection: (lib.evalModules {
    modules = [ homeSurfaceStub ../modules/home.nix { nixagent.home = selection; } ];
  }).config;

  empty = evalWith { };
  claudeOnly = evalWith { upstream = [ "claude-code" ]; };
  allThree = evalWith { upstream = [ "claude-code" "omp" "opencode" ]; };
  warned = evalWith { upstream = [ "claude-code" ]; onInstallFailure = "warn"; };
  noPath = evalWith { upstream = [ "claude-code" ]; addToPath = false; };
  tuned = evalWith { upstream = [ "omp" ]; connectTimeoutSeconds = 3; maxTimeSeconds = 42; };
  codexOnly = evalWith { upstream = [ "openai-codex" ]; };

  script = c: c.home.activation.nixagentUpstream.data;
  contains = needle: hay: lib.hasInfix needle hay;
  occurrences = needle: hay: lib.length (lib.splitString needle hay) - 1;
  sortedList = lib.sort (a: b: a < b);

  # The generated call lines, isolated from the inlined script body they follow. Matching on
  # `nixagent_install_upstream --name` rather than the bare function name is what separates a CALL
  # from the definition and from the usage comment above it.
  callLines = c: lib.filter (l: contains "nixagent_install_upstream --name" l)
    (lib.splitString "\n" (script c));

  installableNames = lib.attrNames
    (lib.filterAttrs (_: t: t.upstream != null)
      (lib.foldl' (acc: g: acc // cat.${g}) { } (lib.attrNames cat)));

  results = {
    # ── The floor ─────────────────────────────────────────────────────────────────────────────
    # An empty selection must leave NO activation entry behind. An entry that exists and does
    # nothing still gets inlined into every activation script, where it is indistinguishable at a
    # glance from one that is failing to do something.
    "an empty selection contributes no activation entry at all -- not an empty one" =
      empty.home.activation == { } && empty.home.sessionPath == [ ];

    "an empty selection publishes empty computed outputs rather than defaults" =
      empty.nixagent.home.binaries == { }
      && empty.nixagent.home.paths == { }
      && empty.nixagent.home.prefixes == [ ];

    # ── THE CONTRACT: NIX ENSURES IT EXISTS, NIX NEVER OWNS IT ────────────────────────────────
    # Mechanised, because it is the entire design and it is exactly the kind of thing a future
    # "wouldn't it be tidier to just add the package" edit would undo. If either of these ever
    # gains a member, this plane has started pinning what it promised never to pin.
    "the module installs NOTHING through nix -- no home.packages, no home.file, on any selection" =
      allThree.home.packages == [ ] && allThree.home.file == { };

    "no version, hash or store path is baked into the rendered script -- the vendor's installer decides the version, every time" =
      !(contains "sha256" (script allThree))
      && !(contains "/nix/store" (script allThree))
      && !(contains "17.2" (script allThree))
      && !(contains "2.1.2" (script allThree));

    # ── The rendered call ─────────────────────────────────────────────────────────────────────
    "the activation entry runs after writeBoundary, so it sees the home this switch is building" =
      claudeOnly.home.activation.nixagentUpstream.after == [ "writeBoundary" ]
      && claudeOnly.home.activation.nixagentUpstream.before == [ ];

    "the installer function is inlined ONCE and called once per selection -- one DAG entry, not one copy of the script per tool" =
      lib.attrNames (allThree.home.activation) == [ "nixagentUpstream" ]
      && occurrences "nixagent_install_upstream() {" (script allThree) == 1
      && lib.length (callLines allThree) == 3
      && lib.length (callLines claudeOnly) == 1;

    "EVERY call honours home-manager's dry-run hook -- `home-manager build` must PRINT the install, never perform it" =
      lib.all (l: lib.hasPrefix "\${DRY_RUN_CMD:-} nixagent_install_upstream --name" l)
        (callLines allThree);

    "the probe is the catalogue's own installs path, and the command is the command -- not the catalogue key and not the package name" =
      contains "--probe '.local/bin/claude'" (script claudeOnly)
      && contains "--command 'claude'" (script claudeOnly)
      && contains "--name 'claude-code'" (script claudeOnly)
      && !(contains "--command 'claude-code'" (script claudeOnly));

    "omp renders its PACKAGE-free identity: probe .local/bin/omp, command omp, and nothing named oh-my-pi-bin -- the AUR package name has no meaning on this plane" =
      contains "--probe '.local/bin/omp'" (script allThree)
      && contains "--command 'omp'" (script allThree)
      && !(contains "oh-my-pi" (script allThree));

    # ── The per-entry installer flags, which are load-bearing ─────────────────────────────────
    # omp's default branch installs to bun's global prefix instead of ~/.local/bin when bun
    # happens to be on the machine, and opencode's default branch appends a PATH line to the
    # user's shell rc. Both are documented at their catalogue entries. Losing either flag would
    # produce a plausible-looking activation that reinstalls forever or edits a generated file.
    "omp is invoked with --binary, so its destination does not depend on whether bun is installed on the host" =
      contains "--url 'https://omp.sh/install' --runner 'sh'" (script allThree)
      && contains "-- '--binary'" (script allThree);

    "opencode is invoked with --no-modify-path, so the installer does not append PATH lines to a home-manager-generated shell rc" =
      contains "-- '--no-modify-path'" (script allThree);

    "claude-code passes no installer flags -- its installer defaults to the latest release, which is what an unpinned delivery mode wants" =
      let calls = lib.filter (l: contains "--name 'claude-code'" l) (callLines allThree);
      in lib.length calls == 1 && !(contains " -- " (lib.head calls));

    # ── The loader flag is emitted per entry, and codex is the case that proves it ────────────
    # Three of the four need /lib64/ld-linux-x86-64.so.2; codex is a static-PIE musl build and
    # needs nothing. Emitting the flag for it would make lib/install-upstream.sh refuse to install
    # on a host with no nix-ld that could have run the binary perfectly well -- so the ABSENCE is
    # the assertion, and it is asserted on the codex call line specifically rather than on the
    # whole script, where another entry's flag would satisfy a naive `contains`.
    "the loader flag is per-entry: emitted for the three glibc installers, absent for codex" =
      lib.all (l: contains "--needs-dynamic-loader" l) (callLines allThree)
      && !(contains "--needs-dynamic-loader" (lib.head (callLines codexOnly)));

    # codex's installer has no --no-modify-path equivalent and prompts unless this variable is set.
    # Rendered as one quoted shell word: `--env 'NAME=VALUE'`, not two arguments.
    #
    # Asserted against the CALL LINES and not the whole script, which is the trap this comment
    # exists for: the activation data is the inlined lib/install-upstream.sh followed by the calls,
    # and that library parses `--env` itself. A `contains` over the script therefore matches the
    # PARSER and would report every entry as rendering an env var.
    "codex renders its non-interactive env var, quoted as a single word, and no other entry renders one" =
      lib.all (l: contains "--env 'CODEX_NON_INTERACTIVE=1'" l) (callLines codexOnly)
      && !(lib.any (l: contains "--env" l) (callLines allThree));

    "codex renders the rest of its identity: sh runner, chatgpt.com installer, probe .local/bin/codex, command codex, and no flags" =
      contains "--url 'https://chatgpt.com/codex/install.sh' --runner 'sh'" (script codexOnly)
      && contains "--probe '.local/bin/codex'" (script codexOnly)
      && contains "--command 'codex'" (script codexOnly)
      && contains "--name 'openai-codex'" (script codexOnly)
      && !(contains " -- " (lib.head (callLines codexOnly)));

    # ── Failure mode and timeouts reach the script ────────────────────────────────────────────
    "the default failure mode is abort -- a switch that goes green without the command is the failure this plane exists to refuse" =
      contains "--on-failure 'abort'" (script claudeOnly)
      && claudeOnly.nixagent.home.onInstallFailure == "abort";

    "onInstallFailure = warn reaches the script rather than being decided in nix" =
      contains "--on-failure 'warn'" (script warned)
      && !(contains "--on-failure 'abort'" (script warned));

    "the timeouts are rendered, so an unreachable network fails instead of hanging the activation forever" =
      contains "--connect-timeout 3" (script tuned)
      && contains "--max-time 42" (script tuned)
      && contains "--connect-timeout 10 --max-time 600" (script claudeOnly);

    # ── PATH ──────────────────────────────────────────────────────────────────────────────────
    # The vendors do not agree on a prefix: claude-code and omp use ~/.local/bin, opencode uses
    # ~/.opencode/bin. Both facts are read out of the catalogue rather than assumed, and the
    # shared one must appear once.
    "sessionPath carries each vendor's OWN prefix, deduplicated -- ~/.local/bin appears once even with two tools in it" =
      allThree.home.sessionPath == [ "/home/tester/.local/bin" "/home/tester/.opencode/bin" ];

    "addToPath = false contributes no sessionPath but still installs -- for a home that manages PATH elsewhere" =
      noPath.home.sessionPath == [ ]
      && noPath.home.activation ? nixagentUpstream
      && noPath.nixagent.home.prefixes == [ "/home/tester/.local/bin" ];

    "the published paths are absolute and match the probes the script will test" =
      allThree.nixagent.home.paths == {
        claude-code = "/home/tester/.local/bin/claude";
        omp = "/home/tester/.local/bin/omp";
        opencode = "/home/tester/.opencode/bin/opencode";
      };

    "binaries maps the selection to real commands on this plane too" =
      allThree.nixagent.home.binaries == {
        claude-code = "claude";
        omp = "omp";
        opencode = "opencode";
      };

    # ── The type is the documentation ─────────────────────────────────────────────────────────
    # An entry with `upstream = null` has no vendor installer (each records what was checked).
    # Selecting one must be an EVAL error, not an activation that fetches nothing: `deepSeq`
    # forces through the lazy listOf-enum merge that rejects it, which `tryEval` alone would not.
    "the selection is typed to entries that HAVE an installer -- naming gemini-cli is refused at eval time, not discovered on a host" =
      (builtins.tryEval (builtins.deepSeq (evalWith { upstream = [ "gemini-cli" ]; }).nixagent.home.upstream true)).success == false;

    "a desktop entry with no vendor installer is refused the same way -- claude-cowork-linux is a third-party repackaging with nothing to run" =
      (builtins.tryEval (builtins.deepSeq (evalWith { upstream = [ "claude-cowork-linux" ]; }).nixagent.home.upstream true)).success == false;

    # openai-codex is deliberately NOT in the refused pair any more -- it moved into the selectable
    # set on 2026-08-11 when its real installer URL was found. Asserted as selectable in the
    # positive direction too, because "no longer an eval error" is exactly the kind of change a
    # negative-only assertion cannot see.
    "openai-codex is selectable, not refused -- the entry whose recorded 403 came from a URL the vendor never used" =
      (builtins.tryEval (builtins.deepSeq codexOnly.nixagent.home.upstream true)).success == true
      && codexOnly.nixagent.home.paths == { openai-codex = "/home/tester/.local/bin/codex"; }
      && codexOnly.nixagent.home.binaries == { openai-codex = "codex"; };

    "the selectable set is DERIVED from the catalogue, not hand-listed here or in the module" =
      sortedList installableNames == [ "claude-code" "omp" "openai-codex" "opencode" ];
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixagent: home-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
