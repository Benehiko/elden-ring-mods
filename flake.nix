{
  description = "elden-ring-mods: what you need to work on the docs, stubs and examples";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # `nix develop` (or direnv's `use flake`) gives you everything the
      # Makefile, the pre-commit hook and CI use. Nothing here builds.
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.gnumake
            pkgs.rumdl # make fmt / make check-fmt (Markdown)
            pkgs.lua5_4 # luac, for the example syntax check
            pkgs.pandoc # make site: docs/*.md to HTML
            pkgs.pagefind # make site: the static search index
          ];
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt-rfc-style);
    };
}
