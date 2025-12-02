{
  description = "A flake for the Leo language.";

  inputs = {
    leo-src = {
      url = "github:provablehq/leo";
      flake = false;
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    systems.url = "github:nix-systems/default";
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
        default = final: prev: {
          leo = prev.callPackage ./pkgs/leo.nix { src = inputs.leo-src; };
        };
      };

      packages = perSystemPkgs (pkgs: {
        leo = pkgs.leo;
        default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.leo;
      });

      devShells = perSystemPkgs (pkgs: {
        leo-dev = pkgs.callPackage ./pkgs/leo-dev.nix { };
        default = inputs.self.devShells.${pkgs.stdenv.hostPlatform.system}.leo-dev;
      });

      formatter = perSystemPkgs (pkgs: pkgs.nixfmt-tree);
    };
}
