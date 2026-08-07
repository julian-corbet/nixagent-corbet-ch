{
  description = "nixagent — agentic AI clients (Claude Code, Claude Cowork, Gemini CLI, Codex, opencode), declared per host and installed from pacman/AUR, never nixpkgs";

  # NO INPUTS FOR CONSUMERS, same reasoning nixmsg and nixdev state for themselves: this flake is
  # options plus a catalogue, taking `pkgs`/`config`/`lib` from whichever evaluation composes it,
  # so a real host never puts a second nixpkgs -- or a sibling flake's whole input closure -- in
  # its own closure.
  inputs = {
    # checks-only. Nothing this flake EXPORTS reaches into it, and the exported module never
    # installs a nixpkgs derivation at all (see modules/nixagent.nix's header: there is no NixOS
    # backend here, on purpose), so this input exists purely to give `nix flake check` a `lib` and
    # a derivation shell to hang the eval-time assertions on.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # Arch / system-manager: the policy module IS the backend, exactly as in nixmsg. Nothing
      # platform-specific is left to do on this plane -- the lists are published for the host's
      # own pacman reconciler to consume, and a second file that only re-exported this one would
      # be an indirection rather than a backend. See modules/nixagent.nix's own header.
      systemManagerModules.nixagent = ./modules/nixagent.nix;
      systemManagerModules.default = ./modules/nixagent.nix;

      # NO `nixosModules` OUTPUT, DELIBERATELY. Every catalogue entry is `nixpkgs = null` by
      # policy -- these tools ship their own updater, which a read-only store path cannot run, and
      # nixpkgs measurably lags every one of them. lib/agents.nix's header carries the numbers.
      # This absence is the repo's boundary, not an unfinished corner.

      # Policy alone, for a consumer that wants the computed lists and will wire them itself, plus
      # the raw catalogue for inspection without re-reading the file. Same split as nixsh's own
      # `lib.policy`/`lib.catalogue` pair.
      lib.policy = ./modules/nixagent.nix;
      lib.catalogue = import ./lib/agents.nix { };

      # `nix flake check` does not evaluate `systemManagerModules` on its own, so a green check on
      # this repo without this file would cover nothing but flake syntax. See the file's own
      # header for what is under test and what deliberately is not.
      checks = forAllSystems (system: {
        agents-eval = import ./checks/agents-eval.nix { pkgs = pkgsFor system; };
      });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
