{
  description = "A flake for the Leo language.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    systems.url = "github:nix-systems/default";
    leo-src = {
      url = "github:provablehq/leo";
      flake = false;
    };
    tree-sitter-leo-src = {
      url = "github:provablehq/leo/v4.0.0";
      flake = false;
    };
    snarkos-src = {
      url = "github:provablehq/snarkos/v4.6.0";
      flake = false;
    };
  };

  outputs =
    inputs:
    let
      overlays = [
        inputs.rust-overlay.overlays.default
        inputs.self.overlays.default
      ];
      perSystemPkgs =
        f:
        inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
          system: f (import inputs.nixpkgs { inherit overlays system; })
        );
    in
    {
      overlays = {
        default =
          final: prev:
          let
            rust = prev.rust-bin.fromRustupToolchainFile "${inputs.leo-src}/rust-toolchain.toml";
          in
          {
            # The main leo CLI binary.
            leo-cli = prev.callPackage ./pkgs/leo-cli.nix {
              src = inputs.leo-src;
              inherit rust;
            };

            # The leo formatter plugin.
            leo-fmt = prev.callPackage ./pkgs/leo-fmt.nix {
              src = inputs.leo-src;
              inherit rust;
            };

            # Combined leo package: CLI + all plugins.
            leo = prev.symlinkJoin {
              name = "leo-${final.leo-cli.version}";
              paths = [
                final.leo-cli
                final.leo-fmt
              ];
            };

            # Default snarkos pkg.
            snarkos = prev.callPackage ./pkgs/snarkos.nix { src = inputs.snarkos-src; };

            # Includes the test_network feature.
            snarkos-testnet = prev.callPackage ./pkgs/snarkos.nix {
              src = inputs.snarkos-src;
              buildFeatures = [ "test_network" ];
            };

            tree-sitter-grammars = prev.tree-sitter-grammars // {
              # Tree-sitter grammar for Leo syntax highlighting.
              tree-sitter-leo = prev.tree-sitter.buildGrammar {
                language = "leo";
                version = "4.0.0";
                src = inputs.tree-sitter-leo-src;
                location = "tree-sitter";
              };
            };

            # Flat alias for easy access alongside inclusion in tree-sitter-grammars.
            tree-sitter-leo = final.tree-sitter-grammars.tree-sitter-leo;
          };
      };

      packages = perSystemPkgs (pkgs: {
        leo = pkgs.leo;
        leo-cli = pkgs.leo-cli;
        leo-fmt = pkgs.leo-fmt;
        snarkos = pkgs.snarkos;
        snarkos-testnet = pkgs.snarkos-testnet;
        tree-sitter-leo = pkgs.tree-sitter-leo;
        default = pkgs.leo;
      });

      devShells = perSystemPkgs (pkgs: {
        leo-dev = pkgs.callPackage ./pkgs/leo-dev.nix { };
        snarkos-dev = pkgs.callPackage ./pkgs/snarkos-dev.nix { };
        default = inputs.self.devShells.${pkgs.stdenv.hostPlatform.system}.leo-dev;
      });

      formatter = perSystemPkgs (pkgs: pkgs.nixfmt-tree);
    };
}
