#!/usr/bin/env bash
# Reproduces the verification every `arch` name in lib/agents.nix was checked against before being
# committed. Run it by hand after touching the catalogue -- repository membership is a fact about
# the world, it changes without this repo changing, and no eval-time check can see it (that is
# exactly the line checks/agents-eval.nix's own header draws around itself).
#
# THREE SOURCES, NOT ONE, and the third is not optional. `pacman -Si` reports which repository a
# name resolves in ON THIS HOST -- which on an Arch DERIVATIVE includes that derivative's own
# repositories. A name can therefore pass `pacman -Si` cleanly and still be in no upstream Arch
# repository at all, which would make `aur = false` correct on the machine running this script and
# a whole-transaction abort on a plain Arch box ("target not found" fails a `pacman -S` atomically
# and takes every unrelated package in the same converge with it). That is not hypothetical: it is
# `claude-code`, the reason `archRepoOn` exists. So:
#
#   1. archlinux.org's package search API  -- upstream Arch, the authority for `aur = false`.
#   2. the AUR RPC                         -- the authority for `aur = true`.
#   3. `pacman -Si`, if pacman is present  -- informational: shows what THIS host resolves, and
#                                             confirms an `archRepoOn` derivative claim when run
#                                             on that derivative.
#
# The nixpkgs side is inverted here compared to every sibling repo's version of this script: there
# is nothing to resolve, because the catalogue's `nixpkgs = null` is a POLICY (these tools
# self-update; a read-only store path cannot run their updater, and nixpkgs measurably lags them --
# see lib/agents.nix's header). That policy is enforced at eval time by checks/agents-eval.nix, so
# it is not re-checked here.
#
# NAMES ARE READ OUT OF lib/agents.nix, never hand-maintained in this file -- a duplicated list
# goes stale in both directions, silently skipping entries that were added and still "verifying"
# entries that were removed.
#
# Usage: ./experiments/verify-package-names.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Pure builtins on purpose: this only reads an attrset of strings, so it must work on a host with
# no <nixpkgs> channel at all.
catalogue_names() {
  local filter="$1"
  nix-instantiate --eval --strict --expr "
    let
      cat = import ./lib/agents.nix { };
      entries = builtins.concatLists (map builtins.attrValues (builtins.attrValues cat));
      want = builtins.filter (t: ${filter}) entries;
    in builtins.concatStringsSep \" \" (map (t: t.arch) want)
  " | sed 's/^\"//; s/\"$//'
}

read -r -a official_names <<<"$(catalogue_names '!(t.aur or false)')"
read -r -a aur_names <<<"$(catalogue_names '(t.aur or false)')"

status=0

echo "== Upstream Arch official repos (archlinux.org package search) -- ${#official_names[@]} name(s) =="
echo "   These carry aur = false, so they MUST exist here or a plain Arch host's pacman transaction aborts."
for pkg in "${official_names[@]}"; do
  count="$(curl -sf "https://archlinux.org/packages/search/json/?name=$pkg" \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["results"]))' 2>/dev/null || echo 0)"
  if [[ "$count" -gt 0 ]]; then
    repo="$(curl -sf "https://archlinux.org/packages/search/json/?name=$pkg" \
      | python3 -c 'import json,sys; r=json.load(sys.stdin)["results"][0]; print(r["repo"], r["pkgver"]+"-"+r["pkgrel"])')"
    echo "OK   $pkg -- $repo"
  else
    echo "FAIL $pkg -- NOT in any upstream Arch repository. lib/agents.nix must mark it aur = true"
    echo "     (with an archRepoOn entry if a derivative's own repository carries it)."
    status=1
  fi
done

echo
echo "== The AUR (aur.archlinux.org RPC v5) -- ${#aur_names[@]} name(s) =="
echo "   These carry aur = true, the safe floor; a derivative may still serve them from its own repo."
for pkg in "${aur_names[@]}"; do
  if curl -sf "https://aur.archlinux.org/rpc/v5/info?arg[]=$pkg" | grep -q '"resultcount":1'; then
    echo "OK   $pkg (AUR)"
  else
    echo "FAIL $pkg -- not in the AUR either. The name in lib/agents.nix is wrong."
    status=1
  fi
done

echo
if command -v pacman >/dev/null 2>&1; then
  echo "== What THIS host resolves (pacman -Si) -- informational, never the authority for \`aur\` =="
  for pkg in "${official_names[@]}" "${aur_names[@]}"; do
    if line="$(pacman -Si "$pkg" 2>/dev/null | sed -n 's/^Repository *: *//p' | head -1)" && [[ -n "$line" ]]; then
      echo "     $pkg -> $line"
    else
      echo "     $pkg -> (no repository on this host; expected for an AUR name here)"
    fi
  done
else
  echo "== pacman not present -- skipping the host-local view (the two authorities above already ran) =="
fi

echo
if [[ $status -eq 0 ]]; then
  echo "All names verified against upstream Arch and the AUR."
else
  echo "One or more names failed verification -- see FAIL lines above." >&2
  exit 1
fi
