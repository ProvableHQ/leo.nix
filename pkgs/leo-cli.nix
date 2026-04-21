{
  makeRustPlatform,
  openssl,
  pkg-config,
  rust,
  src,
}:
let
  rustPlatform = makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };
  buildAndTestSubdir = "crates/leo";
  manifestPath = "${src}/${buildAndTestSubdir}/Cargo.toml";
  manifest = builtins.fromTOML (builtins.readFile manifestPath);
in
rustPlatform.buildRustPackage {
  pname = "leo-cli";
  version = manifest.package.version;
  inherit buildAndTestSubdir src;
  cargoLock.lockFile = "${src}/Cargo.lock";
  nativeBuildInputs = [
    pkg-config
  ];
  buildInputs = [
    openssl
  ];
  doCheck = false; # Tested in CI.
}
