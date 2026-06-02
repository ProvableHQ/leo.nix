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
            mkLeoPkg = prev.callPackage ./pkgs/mk-leo-pkg.nix {
              src = inputs.leo-src;
              inherit rust;
            };

            leoBinManifest = builtins.fromTOML (builtins.readFile ./manifests/leo-bin.toml);
            snarkosBinManifest = builtins.fromTOML (builtins.readFile ./manifests/snarkos-bin.toml);
            mkLeoBin = prev.callPackage ./pkgs/mk-leo-bin.nix { };
            mkSnarkosBin = prev.callPackage ./pkgs/mk-snarkos-bin.nix { };

            mkBinSet =
              builder: manifest:
              let
                byVersion = builtins.mapAttrs (version: data: builder { inherit version data; }) manifest.versions;
              in
              byVersion // { latest = byVersion.${manifest.latest}; };
          in
          {
            # The main leo CLI binary.
            leo-cli = mkLeoPkg {
              pname = "leo-cli";
              crate = "leo";
            };

            # Leo plugins.
            leo-fmt = mkLeoPkg {
              pname = "leo-fmt";
              crate = "fmt";
            };
            leo-lsp = mkLeoPkg {
              pname = "leo-lsp";
              crate = "lsp";
            };

            # Combined leo package: CLI + all plugins.
            leo = prev.symlinkJoin {
              name = "leo-${final.leo-cli.version}";
              paths = [
                final.leo-cli
                final.leo-fmt
                final.leo-lsp
              ];
            };

            # Prebuilt upstream binaries (one combined symlinkJoin per recorded
            # version, plus `latest`). Per-component derivations are exposed as
            # passthru `.cli`, `.fmt`, `.lsp` on each version.
            leo-bin = mkBinSet mkLeoBin leoBinManifest;
            snarkos-bin = mkBinSet mkSnarkosBin snarkosBinManifest;

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

      # Flat, check-friendly outputs: each value is a derivation. The rich
      # versioned attr-set (`leo-bin."4.1.0"`, `leo-bin.latest.cli`, ...) lives
      # under `legacyPackages` below, since `nix flake check` requires every
      # `packages.<system>.<name>` to itself be a derivation.
      packages = perSystemPkgs (
        pkgs:
        let
          lib = pkgs.lib;
          system = pkgs.stdenv.hostPlatform.system;
          # `pkg.meta.platforms` is computed from the manifest's target keys
          # without forcing the per-system target lookup that would `throw` on
          # unsupported hosts, so this stays evaluable everywhere.
          available = pkg: builtins.elem system pkg.meta.platforms;

          leoBinAttrs = lib.optionalAttrs (available pkgs.leo-bin.latest) {
            leo-bin = pkgs.leo-bin.latest;
            leo-cli-bin = pkgs.leo-bin.latest.cli;
            leo-fmt-bin = pkgs.leo-bin.latest.fmt;
            leo-lsp-bin = pkgs.leo-bin.latest.lsp;
          };
          snarkosBinAttrs = lib.optionalAttrs (available pkgs.snarkos-bin.latest) {
            snarkos-bin = pkgs.snarkos-bin.latest;
          };
        in
        {
          leo = pkgs.leo;
          leo-cli = pkgs.leo-cli;
          leo-fmt = pkgs.leo-fmt;
          leo-lsp = pkgs.leo-lsp;
          snarkos = pkgs.snarkos;
          snarkos-testnet = pkgs.snarkos-testnet;
          tree-sitter-leo = pkgs.tree-sitter-leo;
          default = pkgs.leo;
        }
        // leoBinAttrs
        // snarkosBinAttrs
      );

      # Versioned access: `nix shell '.#leo-bin."4.1.0"'` and
      # `nix build '.#legacyPackages.x86_64-linux.leo-bin.latest.cli'`. Flake
      # consumers that want this surface in their own derivations should apply
      # `overlays.default`; `legacyPackages` is the public flake-level handle.
      legacyPackages = perSystemPkgs (
        pkgs:
        let
          lib = pkgs.lib;
          system = pkgs.stdenv.hostPlatform.system;
          available = pkg: builtins.elem system pkg.meta.platforms;
          recurseInto = set: set // { recurseForDerivations = true; };
        in
        lib.optionalAttrs (available pkgs.leo-bin.latest) {
          leo-bin = recurseInto pkgs.leo-bin;
        }
        // lib.optionalAttrs (available pkgs.snarkos-bin.latest) {
          snarkos-bin = recurseInto pkgs.snarkos-bin;
        }
      );

      apps = perSystemPkgs (
        pkgs:
        let
          update-bin-manifest = pkgs.writeShellApplication {
            name = "update-bin-manifest";
            runtimeInputs = with pkgs; [
              cacert
              coreutils
              curl
              git
              jq
              nix
              yj
            ];
            text = builtins.readFile ./scripts/update-bin-manifest.sh;
          };
          update-manifests = pkgs.writeShellApplication {
            name = "update-manifests";
            runtimeInputs =
              (with pkgs; [
                cacert
                coreutils
                curl
                git
                jq
                yj
              ])
              ++ [ update-bin-manifest ];
            text = builtins.readFile ./scripts/update-manifests.sh;
          };
        in
        {
          update-bin-manifest = {
            type = "app";
            program = "${update-bin-manifest}/bin/update-bin-manifest";
          };
          update-manifests = {
            type = "app";
            program = "${update-manifests}/bin/update-manifests";
          };
        }
      );

      devShells = perSystemPkgs (pkgs: {
        leo-dev = pkgs.callPackage ./pkgs/leo-dev.nix { };
        snarkos-dev = pkgs.callPackage ./pkgs/snarkos-dev.nix { };
        default = inputs.self.devShells.${pkgs.stdenv.hostPlatform.system}.leo-dev;
      });

      formatter = perSystemPkgs (pkgs: pkgs.nixfmt-tree);
    };
}
