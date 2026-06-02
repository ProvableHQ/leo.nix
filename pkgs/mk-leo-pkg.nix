{
  lib,
  llvmPackages,
  makeRustPlatform,
  openssl,
  pkg-config,
  rocksdb,
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
    llvmPackages.bintools
    pkg-config
    rustPlatform.bindgenHook
  ];
  buildInputs = [
    openssl
    rocksdb
  ];
  doCheck = false; # Tested in CI.
  # Dynamically link to rocksdb.
  ROCKSDB_LIB_DIR = lib.makeLibraryPath [ rocksdb ];
}
