{
  makeRustPlatform,
  openssl,
  pkg-config,
  rust,
  src,
}:
{
  pname,
  crate,
}:
let
  rustPlatform = makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };
  buildAndTestSubdir = "crates/${crate}";
  manifestPath = "${src}/${buildAndTestSubdir}/Cargo.toml";
  manifest = builtins.fromTOML (builtins.readFile manifestPath);
in
rustPlatform.buildRustPackage {
  inherit pname buildAndTestSubdir src;
  version = manifest.package.version;
  cargoLock.lockFile = "${src}/Cargo.lock";
  nativeBuildInputs = [
    pkg-config
  ];
  buildInputs = [
    openssl
  ];
  doCheck = false; # Tested in CI.
}
