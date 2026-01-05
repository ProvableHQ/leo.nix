{
  buildFeatures ? [ ],
  buildNoDefaultFeatures ? false,
  lib,
  libclang,
  lld,
  makeRustPlatform,
  openssl,
  pkg-config,
  rocksdb,
  rust-bin,
  src,
}:
let
  rust = rust-bin.fromRustupToolchainFile "${src}/rust-toolchain.toml";
  rustPlatform = makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };
  manifestPath = "${src}/Cargo.toml";
  manifest = builtins.fromTOML (builtins.readFile manifestPath);
in
rustPlatform.buildRustPackage {
  pname = "snarkos";
  version = manifest.package.version;
  src = src;
  # The `cargo-auditable` used by `buildRustPackage` appears to be out-of-date.
  auditable = false;
  inherit buildFeatures buildNoDefaultFeatures;
  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "snarkvm-4.4.0" = "sha256-CIFrw8/CrjLYak215ggF0yuOFheeP3+cjLrJR5xYLlQ=";
    };
  };
  nativeBuildInputs = [
    libclang
    lld
    pkg-config
  ];
  buildInputs = [
    openssl
    rocksdb
  ];
  doCheck = false; # Tested in CI.
  LIBCLANG_PATH = lib.makeLibraryPath [ libclang ];
  # Dynamically link to rocksdb.
  ROCKSDB_LIB_DIR = lib.makeLibraryPath [ rocksdb ];
}
