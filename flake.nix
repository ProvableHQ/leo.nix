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
    snarkos-src = {
      # Pinned to recent `canary-v4.5.0` commit.
      url = "github:provablehq/snarkos?rev=4ec22a328d3dc583a13899b2836488a4e4e647f2";
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
            # Provide versions of leo built with both the officially supported
            # rust version, as well as a rust nightly compiler to allow
            # build-time profiling.
            rust = prev.rust-bin.fromRustupToolchainFile "${inputs.leo-src}/rust-toolchain.toml";
            rust-nightly = prev.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
          in
          {
            # Stable, official leo.
            leo = prev.callPackage ./pkgs/leo.nix {
              src = inputs.leo-src;
              rust = rust;
            };

            # Leo built with nightly rust.
            leo-rust-nightly = prev.callPackage ./pkgs/leo.nix {
              src = inputs.leo-src;
              rust = rust-nightly;
            };

            # Default snarkos pkg.
            snarkos = prev.callPackage ./pkgs/snarkos.nix { src = inputs.snarkos-src; };

            # Includes the test_network feature.
            snarkos-testnet = prev.callPackage ./pkgs/snarkos.nix {
              src = inputs.snarkos-src;
              buildFeatures = [ "test_network" ];
            };
          };
      };

      packages = perSystemPkgs (pkgs: {
        leo = pkgs.leo;
        leo-rust-nightly = pkgs.leo-rust-nightly;
        snarkos = pkgs.snarkos;
        snarkos-testnet = pkgs.snarkos-testnet;
        default = pkgs.leo;
      });

      devShells = perSystemPkgs (pkgs: {
        leo-dev = pkgs.callPackage ./pkgs/leo-dev.nix { };
        leo-nightly-dev = pkgs.callPackage ./pkgs/leo-dev.nix { leo = pkgs.leo-rust-nightly; };
        snarkos-dev = pkgs.callPackage ./pkgs/snarkos-dev.nix { };
        default = inputs.self.devShells.${pkgs.stdenv.hostPlatform.system}.leo-dev;
      });

      formatter = perSystemPkgs (pkgs: pkgs.nixfmt-tree);
    };
}
