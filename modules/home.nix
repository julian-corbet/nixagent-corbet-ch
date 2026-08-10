#
# nixagent's HOME-MANAGER plane: the second delivery mode. Runs each selected tool's OWN upstream
# installer, once, into that vendor's own per-user prefix, and puts the result on PATH.
#
# WHY THIS PLANE EXISTS. ./nixagent.nix publishes pacman/AUR package names for a host that
# reconciles distro packages. Two kinds of host get nothing useful out of that:
#
#   - a NixOS host, which has no pacman at all. Its only nix-native option would be a nixpkgs
#     derivation, which is the one thing this repo refuses (../lib/agents.nix's header carries the
#     measurements: these tools ship their own updater, and a read-only store path cannot run it).
#   - ANY host wanting a tool whose distro package has fallen behind. Measured 2026-08-10: the AUR
#     carried omp 17.2.2/17.2.3 against an upstream 17.2.12, both packages flagged out of date,
#     both with an updater bot as co-maintainer. The AUR is a human in the loop of a project that
#     ships several times a week, and for a fast enough project it pins as badly as nixpkgs would.
#
# THE CONTRACT, stated once here and enforced in ../lib/install-upstream.sh: nix's job is to make
# sure the tool EXISTS and is on PATH. Nix never owns the binary, never learns its version, never
# rewrites it. There is deliberately no `home.packages` entry, no `home.file` for a binary and no
# hash anywhere on this plane -- checks/home-eval.nix asserts the absence, because that absence IS
# the design. Afterwards the tool's own `update` command keeps working, which is the entire reason
# to install it this way rather than any other.
#
# WHY HOME-MANAGER AND NOT system-manager/NixOS. The installers put things under $HOME and refuse
# to run as root (Anthropic's exits with an explanation if invoked under sudo). A per-user prefix
# is a per-user concern, and this is the plane that has a user.
#
# THE TWO PLANES ARE CHOSEN PER HOST BY THE CONSUMER and share no state -- system-manager and
# home-manager are separate evaluations with no common `config` to read across, the same boundary
# ../README.md's sibling repos document for themselves. A host picks pacman/AUR, or upstream, or
# (legitimately) both for different tools. The one case where they can collide -- the same command
# arriving from both -- cannot be seen at eval time from either side, so ../lib/install-upstream.sh
# reports it at activation, where both are finally visible.
#
# ONE NAMESPACE. Everything here lives under `nixagent.home`, like every repo in this family.
{ config, lib, ... }:
let
  cfg = config.nixagent.home;
  cat = import ../lib/agents.nix { };

  # Groups flattened into ONE selection space. The distro plane keeps `cli` and `desktop` apart
  # because a pacman list and a desktop-app list are genuinely different things to a reconciler;
  # here they would be the same list, since what decides selectability is whether the entry has a
  # vendor installer, not whether it draws a window. Keys are unique across groups and
  # checks/agents-eval.nix asserts it, so this merge cannot silently drop an entry.
  entries = lib.foldl' (acc: g: acc // cat.${g}) { } (lib.attrNames cat);

  # THE SELECTABLE SET IS DERIVED, NOT HAND-LISTED. An entry with `upstream = null` has no vendor
  # installer (see its own comment for what was checked), so naming it here is a type error at
  # eval time rather than an activation that fetches nothing. That is the whole reason the field
  # is `null` on every such entry rather than absent.
  installable = lib.filterAttrs (_: t: t.upstream != null) entries;

  selected = map (k: installable.${k} // { name = k; }) cfg.upstream;

  homeDir = config.home.homeDirectory;
  prefixOf = t: "${homeDir}/${builtins.dirOf t.upstream.installs}";

  # ALWAYS quote, rather than `lib.escapeShellArg`. Measured against the pinned nixpkgs
  # (b7c2ada, 2026-08-10): `escapeShellArg ".local/bin/claude"` returns `.local/bin/claude`,
  # unquoted -- current nixpkgs omits the quotes whenever it judges a string safe. The judgement
  # is sound and the result is a correct shell word either way, but WHICH form comes out is a
  # nixpkgs implementation detail, and what this module renders is a shipped artifact whose exact
  # text checks/home-eval.nix pins. Quoting unconditionally means a nixpkgs bump cannot silently
  # reshape an activation script or turn a passing check into a failing one for no reason a reader
  # of this repo could find. The escaping itself is the standard one: close, escaped quote, reopen.
  shq = s: "'" + lib.replaceStrings [ "'" ] [ "'\\''" ] s + "'";

  # One call line per selection, into the function ../lib/install-upstream.sh defines.
  #
  # `${DRY_RUN_CMD:-}` is home-manager's own dry-run hook: it is empty during a real activation and
  # `echo` during `home-manager build`/`--dry-run`, so a dry run PRINTS the call instead of making
  # a network request. Without it, "show me what a switch would do" would install things.
  #
  # Every value is quoted. None of them contains a space today; a URL or a future installer flag
  # that did would otherwise turn into two arguments and produce a failure that reads like a broken
  # installer rather than a quoting bug.
  installCall = t: lib.concatStringsSep " " (
    [
      "\${DRY_RUN_CMD:-}"
      "nixagent_install_upstream"
      "--name"
      (shq t.name)
      "--command"
      (shq t.binary)
      "--probe"
      (shq t.upstream.installs)
      "--url"
      (shq t.upstream.url)
      "--runner"
      (shq t.upstream.runner)
      "--on-failure"
      (shq cfg.onInstallFailure)
      "--connect-timeout"
      (toString cfg.connectTimeoutSeconds)
      "--max-time"
      (toString cfg.maxTimeSeconds)
    ]
    ++ lib.optionals (t.upstream.args != [ ]) ([ "--" ] ++ map shq t.upstream.args)
  );

  # ONE activation entry for the whole selection, not one per tool. The script body is inlined
  # once and called N times; N separate DAG entries would inline N copies of it and buy nothing,
  # since they would run in sequence anyway.
  #
  # Written as the literal DAG record `{ data; before; after; }` rather than through
  # `lib.hm.dag.entryAfter`, which is exactly what that helper returns. `lib.hm` only exists
  # inside a real home-manager evaluation, and depending on it would make this module impossible
  # to evaluate -- and therefore impossible to CHECK -- outside one. checks/home-eval.nix
  # evaluates this file against a stub of the handful of home-manager options it writes to, which
  # only works because of this.
  #
  # After `writeBoundary`: home.sessionPath and every managed file are in place first, so the
  # installer runs against the home this activation is building rather than the previous one.
  # Prepended to PATH for the duration of the install, and ONLY for it -- this is a local `PATH=`
  # on the activation's own environment, not `home.sessionPath`, because nothing here belongs in
  # the user's interactive shell. Empty by default, which renders no line at all.
  pathPrelude = lib.optionalString (cfg.extraPath != [ ])
    "PATH=${lib.concatStringsSep ":" cfg.extraPath}\${PATH:+:$PATH}\nexport PATH\n";

  activationEntry = {
    before = [ ];
    after = [ "writeBoundary" ];
    data = ''
      ${pathPrelude}${builtins.readFile ../lib/install-upstream.sh}
      ${lib.concatMapStringsSep "\n" installCall selected}
    '';
  };
in
{
  options.nixagent.home = {
    upstream = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames installable));
      default = [ ];
      example = [ "claude-code" "omp" ];
      description = ''
        Which agents to install from their OWN upstream installer into this user's home, rather
        than from pacman/AUR. Available: ${lib.concatStringsSep ", " (lib.attrNames installable)}.

        This is the delivery mode for a host with no distro package manager to reconcile (a NixOS
        box gets these tools no other way here), and for any tool whose distro package has fallen
        behind upstream -- which the AUR measurably does for a fast-moving entry, see
        lib/agents.nix's own header.

        The list is typed to the catalogue entries that HAVE a vendor installer. Naming one that
        does not (`gemini-cli`, `openai-codex`, `claude-cowork-linux` -- each records what was
        checked) fails at eval time, which is the point: the alternative is an activation that
        looks fine and installs nothing.

        NIX DOES NOT OWN WHAT THIS INSTALLS. The installer runs once, when the tool is absent, and
        never again while it is present; from then on the tool updates itself, which is the
        property this whole repo exists to preserve. No version is pinned here and none can be.
      '';
    };

    onInstallFailure = lib.mkOption {
      type = lib.types.enum [ "abort" "warn" ];
      default = "abort";
      description = ''
        What a failed install does to the activation.

        `abort` (default) fails the whole `home-manager switch`. That is the right default because
        the failure this module is most likely to hit is the quiet one -- an installer that
        changed, a URL that now 404s, a download that returned an HTML error page -- and a switch
        that goes green while leaving the operator without the command is precisely the outcome
        the verification in lib/install-upstream.sh was written to prevent.

        `warn` prints the SAME diagnostic block to stderr and lets the activation finish. For a
        machine that legitimately switches while offline (a laptop) and would rather have the rest
        of its home applied. It is a quieter failure, never a silent one: the block still names
        the stage, the installer's own output, and the fact that the command is unavailable.

        Neither setting affects a malformed call into the installer script itself, which is a bug
        in this repo and always fails hard.
      '';
    };

    addToPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Publish each selected tool's install directory through `home.sessionPath`, so the command
        is actually reachable. On by default because "the binary exists but is not on PATH" is not
        a delivered tool -- half the contract this module states.

        The directories come from the catalogue (`upstream.installs`), so they are whatever each
        VENDOR chose: `~/.local/bin` for claude-code and omp, `~/.opencode/bin` for opencode.
        Duplicates collapse.

        Turn it off only if the PATH is managed somewhere else. Note that opencode's installer
        would otherwise append a PATH line to a shell rc file itself -- this module passes
        `--no-modify-path` to stop it (see lib/agents.nix), so switching this off on a host that
        selects opencode leaves the directory on no PATH at all.
      '';
    };

    extraPath = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''
        map (p: "''${p}/bin") (with pkgs; [ curl bash coreutils gnutar gzip unzip ])
      '';
      description = ''
        Directories prepended to `PATH` for the upstream install, and for nothing else. Empty by
        default, and on a host with an FHS it can stay that way -- `/usr/bin` already carries
        everything a vendor installer reaches for.

        IT CANNOT STAY EMPTY ON A NIX-MANAGED HOST, and the failure without it is not obvious.
        A home-manager activation runs from a systemd unit, not a login shell, so it inherits
        neither the user's `PATH` nor `home.sessionPath`. On NixOS that leaves the install with
        essentially nothing: no `curl` to fetch the installer, no `bash` to run it, and none of the
        `tar`/`unzip`/`uname` the installers themselves call. The preflight in
        `lib/install-upstream.sh` tests the first two by name and reports this option, rather than
        letting the vendor script fail at 127 in a way that reads like a network fault.

        A LIST OF DIRECTORIES, not of packages, and deliberately so: this repo carries no nixpkgs
        in its closure and installs nothing, so it cannot name `pkgs.curl` itself. Which store
        paths satisfy it is the consumer's answer, the same way every other package identity in
        this family of repos is.

        Scoped to the activation on purpose. These tools exist for the installer's benefit; putting
        them on the user's own `PATH` would be this module deciding which coreutils a human gets.
      '';
    };

    connectTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = ''
        curl `--connect-timeout` for fetching an installer. An activation that hangs forever on an
        unreachable network is worse than one that fails: the switch never returns, and on a
        machine that switches from a unit there is nothing to see. Ten seconds is enough for any
        reachable host and short enough that an unreachable one is reported rather than waited on.
      '';
    };

    maxTimeSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        curl `--max-time` for fetching an installer, i.e. the ceiling on the whole transfer. This
        bounds the DOWNLOAD OF THE SCRIPT only -- the installer then does its own fetching with
        its own timeouts, which this module does not attempt to override. Generous on purpose: the
        cost of it being too low is a spurious failure on a slow link.
      '';
    };

    # ── Computed, read-only ─────────────────────────────────────────────────────────────────────
    binaries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = ''
        catalogue name -> the command actually installed, for this plane's selection. Same trap as
        the system plane's `nixagent.binaries`: the key is not the command (`claude-code` installs
        `claude`), and here the package name is not either (`omp`'s pacman name is `oh-my-pi-bin`).
      '';
    };

    paths = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = ''
        catalogue name -> the absolute path the vendor's installer creates. This is the exact path
        used as the idempotency probe at activation time, published so an operator can check by
        hand what the module will look for before deciding it is broken.
      '';
    };

    prefixes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        The deduplicated directories added to `home.sessionPath` when `addToPath` is on. Published
        separately so a consumer that manages PATH itself can wire exactly these and turn the
        option off, rather than re-deriving them from the catalogue.
      '';
    };
  };

  config = {
    nixagent.home.binaries = lib.listToAttrs (map (t: lib.nameValuePair t.name t.binary) selected);
    nixagent.home.paths = lib.listToAttrs (map (t: lib.nameValuePair t.name "${homeDir}/${t.upstream.installs}") selected);
    nixagent.home.prefixes = lib.unique (map prefixOf selected);

    # mkIf on both, so a home that selects nothing contributes NO activation entry and NO PATH
    # element rather than an empty one -- an empty activation entry would still be inlined into
    # the activation script, which is the sort of "does nothing, loudly" that makes a real one
    # harder to spot.
    home.activation = lib.mkIf (selected != [ ]) { nixagentUpstream = activationEntry; };
    home.sessionPath = lib.mkIf (cfg.addToPath && selected != [ ]) cfg.prefixes;
  };
}
