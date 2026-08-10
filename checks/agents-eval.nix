# Evaluates modules/nixagent.nix for real against `lib.evalModules` and asserts what it resolves --
# the same "Nix inspecting Nix" tier as nixsh's checks/tools-eval.nix, and here for the same reason
# that file states: `nix flake check` does NOT evaluate `systemManagerModules` on its own, so a
# green check on this repo without a file like this one would prove nothing but flake syntax.
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell. Every question this
# repo can actually answer at eval time is a question about NAMES and LISTS -- which group a key
# belongs to, which side of the pacman/AUR split a name lands on for a given distro, whether the
# nixpkgs prohibition still holds -- and none of them needs a package set. Unlike its siblings this
# repo has no nixpkgs-resolution half to check at all: `nixpkgs = null` everywhere is the policy,
# and asserting THAT is one of the checks below rather than something a real `pkgs` would help with.
#
# SCOPE, now that there are two delivery modes. This file owns the SYSTEM plane
# (../modules/nixagent.nix: the pacman/AUR split) plus every assertion about the CATALOGUE itself,
# including the shape of the `upstream` field the second mode reads. How that field resolves into
# a home-manager activation is ./home-eval.nix, and whether the resulting script actually behaves
# is ./upstream-install.nix -- which runs it rather than asserting about it.
#
# What can NOT be proven here, and is not pretended: whether `claude-code` is in a given
# repository today, or whether an installer URL still answers. Those are facts about the world,
# they change without this repo changing, and they are verified out of band against live sources
# -- see ../experiments/verify-package-names.sh.
{ pkgs, lib ? pkgs.lib }:
let
  cat = import ../lib/agents.nix { };

  evalWith = selection: (lib.evalModules {
    modules = [ ../modules/nixagent.nix { nixagent = selection; } ];
  }).config.nixagent;

  allClients = lib.attrNames cat.cli;
  allDesktop = lib.attrNames cat.desktop;
  allSelectable = lib.length allClients + lib.length allDesktop;

  # The whole catalogue, on each of the two distro answers. Both fixtures matter: the arch/AUR
  # split is not a property of the catalogue alone here, it is a property of the catalogue AND the
  # host, so a check that only ever evaluated one of them would leave half the resolution untested.
  # Both groups selected together -- `cli` and `desktop` share one `selected` list, and a fixture
  # that only ever populated one group would leave the other's contribution to the shared
  # archPackages/aurPackages split untested.
  archAll = evalWith { cli = allClients; desktop = allDesktop; distro = "arch"; };
  cachyAll = evalWith { cli = allClients; desktop = allDesktop; distro = "cachyos"; };

  empty = evalWith { };

  has = list: item: lib.elem item list;
  sorted = lib.sort (a: b: a < b);

  # Every entry in the catalogue, group-blind. The `upstream` assertions below are properties of
  # an ENTRY rather than of a group, and ../modules/home.nix flattens the groups the same way.
  allEntries = lib.concatMap (g: lib.attrValues cat.${g}) (lib.attrNames cat);
  allKeys = lib.concatMap (g: lib.attrNames cat.${g}) (lib.attrNames cat);
  withUpstream = lib.filter (t: t.upstream != null) allEntries;

  results = {
    # ── The floor: nothing selected must produce nothing at all ────────────────────────────────
    "empty selection resolves to nothing selected" =
      empty.selected == [ ];

    "empty selection produces empty package lists on BOTH sides, not one populated by default" =
      empty.archPackages == [ ] && empty.aurPackages == [ ] && empty.binaries == { };

    # ── THE LOAD-BEARING INVARIANT ────────────────────────────────────────────────────────────
    # One AUR name reaching a pacman list aborts the entire pacman transaction ("target not
    # found") and takes every unrelated package in the same converge down with it. Asserted on
    # both distro answers, because that is exactly where an entry can move between the lists.
    "archPackages and aurPackages never intersect -- the whole-transaction abort this split exists to prevent (distro = arch)" =
      lib.intersectLists archAll.archPackages archAll.aurPackages == [ ];

    "archPackages and aurPackages never intersect (distro = cachyos)" =
      lib.intersectLists cachyAll.archPackages cachyAll.aurPackages == [ ];

    "every selection lands on exactly one of the two lists -- none silently dropped, none counted twice (both distros)" =
      lib.length (archAll.archPackages ++ archAll.aurPackages) == allSelectable
      && lib.length (cachyAll.archPackages ++ cachyAll.aurPackages) == allSelectable;

    # ── Group wiring ──────────────────────────────────────────────────────────────────────────
    # Hand-listed groups in modules/nixagent.nix are cheap and readable; the failure they invite
    # is a catalogue group that never gets an option. This closes it: adding a group to
    # lib/agents.nix without wiring it fails the check rather than resolving to nothing forever.
    "every catalogue group has a matching selection option on the module" =
      lib.all (g: (evalWith { }) ? ${g}) (lib.attrNames cat);

    "every group contributes to \`selected\` -- selecting the whole catalogue resolves every entry (cli: 5, desktop: 1, total: 6)" =
      lib.length archAll.selected == 6
      && lib.length archAll.selected == allSelectable;

    "each group's option is typed to its OWN keys -- a name from another group (or a typo) is refused at eval time, not silently ignored" =
      # `evalModules` is lazy: `tryEval` alone forces only WHNF (the attrset exists), never the
      # type-checked value inside. `deepSeq` forces through, which is what actually runs the
      # listOf-enum merge that rejects the name.
      (builtins.tryEval (builtins.deepSeq (evalWith { cli = [ "lmstudio-bin" ]; }).cli true)).success == false;

    "the \`desktop\` option is typed to its OWN keys too -- a \`cli\` name is refused as a desktop selection" =
      (builtins.tryEval (builtins.deepSeq (evalWith { desktop = [ "claude-code" ]; }).desktop true)).success == false;

    # ── THE REPO'S REASON TO EXIST, MECHANISED ────────────────────────────────────────────────
    # These tools self-update and nixpkgs lags them (measured -- see lib/agents.nix's header), so
    # the catalogue installs from pacman/AUR and never from nixpkgs. Asserted over the RAW
    # catalogue rather than a selection, so an entry that is not yet selectable anywhere is still
    # covered the moment it is written.
    "every catalogue entry carries nixpkgs = null -- the AUR/pacman-never-nixpkgs policy, enforced rather than merely documented" =
      lib.all (t: t ? nixpkgs && t.nixpkgs == null)
        (lib.concatMap (g: lib.attrValues cat.${g}) (lib.attrNames cat));

    "the module publishes no nixpkgs-facing option at all -- no nixosPackages, no unavailableOnNixos; there is no NixOS backend to feed and a half-built one would be worse than none" =
      let o = evalWith { }; in
      !(o ? nixosPackages) && !(o ? unavailableOnNixos) && !(o ? nixpkgsPackages);

    # ── The distro-dependent entry ────────────────────────────────────────────────────────────
    # claude-code is in no upstream Arch repository (archlinux.org search: 0 results) but IS in
    # CachyOS's own repo and in the AUR. It is the only entry whose correct list depends on the
    # host, and the reason `archRepoOn`/`nixagent.distro` exist -- so pin the behaviour here where
    # a future edit cannot quietly undo it.
    "claude-code is AUR on plain Arch -- the safe floor, since upstream Arch packages it nowhere" =
      has archAll.aurPackages "claude-code" && !(has archAll.archPackages "claude-code");

    "claude-code moves to the pacman list on a distro whose own repository carries it" =
      has cachyAll.archPackages "claude-code" && !(has cachyAll.aurPackages "claude-code");

    "the default distro is the recoverable one: a host that declares nothing gets claude-code from the AUR, never a pacman target that may not resolve" =
      let d = evalWith { cli = [ "claude-code" ]; }; in
      d.aurPackages == [ "claude-code" ] && d.archPackages == [ ];

    "claude-cowork-linux is AUR on EVERY distro -- unlike claude-code, it carries no archRepoOn, so there is no repository lift to apply on any of them" =
      has archAll.aurPackages "claude-cowork-linux" && !(has archAll.archPackages "claude-cowork-linux")
      && has cachyAll.aurPackages "claude-cowork-linux" && !(has cachyAll.archPackages "claude-cowork-linux");

    "`archRepoOn` is scoped to the entry that needs it -- it does not leak an official-repo claim onto the rest of the catalogue on ANY distro" =
      sorted cachyAll.aurPackages == [ "claude-cowork-linux" "oh-my-pi-bin" ]
      && sorted archAll.aurPackages == [ "claude-code" "claude-cowork-linux" "oh-my-pi-bin" ];

    # omp is in no upstream Arch repository and in no derivative's repository either (all three of
    # `oh-my-pi-bin`, `oh-my-pi` and `omp` checked 2026-08-10 -- see its catalogue entry), so it
    # carries no `archRepoOn` and must stay on the AUR list whatever the host says it runs. Pinned
    # separately from the claude-cowork-linux case above because they got there for different
    # reasons and a future `archRepoOn` on either would silently pass the other's assertion.
    "omp is AUR on EVERY distro, under its PACKAGE name -- the key `omp` is the tool, `oh-my-pi-bin` is the package, and only the latter may reach a package list" =
      has archAll.aurPackages "oh-my-pi-bin" && has cachyAll.aurPackages "oh-my-pi-bin"
      && !(has archAll.archPackages "oh-my-pi-bin") && !(has cachyAll.archPackages "oh-my-pi-bin")
      && !(has (archAll.archPackages ++ archAll.aurPackages) "omp")
      && !(has (archAll.archPackages ++ archAll.aurPackages) "oh-my-pi");

    "the three upstream-Arch entries stay on the pacman list regardless of distro -- their repository membership is not derivative-dependent" =
      lib.all (n: has archAll.archPackages n && has cachyAll.archPackages n)
        [ "gemini-cli" "openai-codex" "opencode" ];

    # ── Package name vs command name ──────────────────────────────────────────────────────────
    # Three of the four disagree. A consumer aliasing, wrapping or launching by the PACKAGE name
    # gets a command that does not exist, which is what `binaries` is published to prevent.
    "binaries maps every selection to its real command, not its package name" =
      archAll.binaries == {
        claude-code = "claude";
        gemini-cli = "gemini";
        openai-codex = "codex";
        opencode = "opencode";
        omp = "omp";
        claude-cowork-linux = "claude-cowork";
      };

    # omp is the sharpest case in the catalogue: catalogue key `omp`, pacman name `oh-my-pi-bin`,
    # npm name `@oh-my-pi/pi-coding-agent`, command `omp`. It is also the entry that broke the
    # coincidence that every key equalled its `arch` value -- see lib/agents.nix's own section on
    # why the key names the TOOL rather than one delivery mode's package.
    "the omp key/package/command divergence is pinned -- the key is not the package name, and the package name is not the command" =
      archAll.binaries.omp == "omp"
      && has archAll.aurPackages "oh-my-pi-bin"
      && (cat.cli.omp.arch == "oh-my-pi-bin");

    "the codex package/command divergence is pinned in both directions -- the pacman name is openai-codex, the command is codex, and neither is usable in the other's place" =
      has archAll.archPackages "openai-codex"
      && !(has archAll.archPackages "codex")
      && archAll.binaries.openai-codex == "codex";

    "binaries covers exactly the selection, no more -- an unselected entry contributes no command" =
      let d = evalWith { cli = [ "opencode" ]; }; in
      d.binaries == { opencode = "opencode"; };

    # ── Catalogue integrity ───────────────────────────────────────────────────────────────────
    "every catalogue entry names both a package and a command -- a missing `binary` would make `nixagent.binaries` silently wrong rather than absent" =
      lib.all (t: t ? arch && t ? binary && lib.isString t.arch && lib.isString t.binary)
        (lib.concatMap (g: lib.attrValues cat.${g}) (lib.attrNames cat));

    "`archRepoOn` only ever appears on an entry that is AUR-only upstream -- on an official-repo entry it would be a no-op that reads like a promise" =
      lib.all (t: !(t ? archRepoOn) || (t.aur or false))
        (lib.concatMap (g: lib.attrValues cat.${g}) (lib.attrNames cat));

    "every `archRepoOn` names a distro `nixagent.distro` can actually be set to -- a typo'd derivative would silently never match" =
      lib.all (d: lib.elem d [ "arch" "cachyos" ])
        (lib.concatMap (t: t.archRepoOn or [ ])
          (lib.concatMap (g: lib.attrValues cat.${g}) (lib.attrNames cat)));

    # ── The SECOND delivery mode's catalogue half ─────────────────────────────────────────────
    # ../modules/home.nix runs `upstream.url` with `upstream.runner` and then probes
    # `upstream.installs`. Every one of those is a string that reaches a shell or a filesystem
    # test at activation time on a real machine, so the shape is asserted here where a typo costs
    # a failed `nix flake check` rather than a failed switch on three hosts.

    "every catalogue entry carries an `upstream` field -- null where the vendor ships no installer, so a blank cannot be mistaken for an unresearched entry" =
      lib.all (t: t ? upstream) allEntries;

    "every non-null `upstream` names an https URL, an interpreter that exists, an args LIST and an installed path" =
      lib.all
        (t:
          lib.isString t.upstream.url
          && lib.hasPrefix "https://" t.upstream.url
          && lib.elem t.upstream.runner [ "bash" "sh" ]
          && lib.isList t.upstream.args
          && lib.all lib.isString t.upstream.args
          && lib.isString t.upstream.installs)
        withUpstream;

    # `installs` is joined onto $HOME by lib/install-upstream.sh. An absolute path or a `$HOME`
    # of its own would produce `/home/x//home/x/...` or an unexpanded literal, and the probe would
    # then never match -- which reads as "reinstalls on every activation", the exact regression
    # the idempotency gate exists to prevent.
    "every `upstream.installs` is RELATIVE to $HOME -- no leading slash, no embedded $HOME, no traversal" =
      lib.all
        (t:
          !(lib.hasPrefix "/" t.upstream.installs)
          && !(lib.hasPrefix "~" t.upstream.installs)
          && !(lib.hasInfix "$" t.upstream.installs)
          && !(lib.hasInfix ".." t.upstream.installs))
        withUpstream;

    # The probe path IS the command. If they diverge, the module verifies one file and puts a
    # different one on PATH -- and the divergence would only show up as "the tool installed fine
    # but the command is missing", on a host, after a switch.
    "every `upstream.installs` ends in the entry's own `binary` -- the idempotency probe and the command on PATH are the same file" =
      lib.all (t: builtins.baseNameOf t.upstream.installs == t.binary) withUpstream;

    # Not a style rule. modules/home.nix merges `cli` and `desktop` into one selection space, so a
    # key appearing in both groups would resolve to whichever group merged last, silently.
    "catalogue keys are unique across ALL groups -- the home-manager plane flattens them into one selection space" =
      lib.length allKeys == lib.length (lib.unique allKeys);

    # The three entries that carry `upstream = null` each record what was checked (npm-only
    # distribution, a 404/403 on the plausible installer URL, or a third-party repackaging with no
    # vendor installer to run). Pinned so that "add an installer URL" stays a deliberate edit with
    # a measurement behind it rather than something a refactor can invent.
    "exactly the researched entries carry a vendor installer -- claude-code, opencode and omp; gemini-cli, openai-codex and claude-cowork-linux carry a recorded null" =
      sorted
        (lib.attrNames (lib.filterAttrs (_: t: t.upstream != null)
          (lib.foldl' (acc: g: acc // cat.${g}) { } (lib.attrNames cat))))
      == [ "claude-code" "omp" "opencode" ];
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixagent: agents-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
