{
  buildFeatures ? [ ],
  buildNoDefaultFeatures ? false,
  lib,
  libclang,
  llvmPackages,
  makeRustPlatform,
  openssl,
  pkg-config,
  rocksdb,
  rust-bin,
  src,
  zlib,
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
      "snarkvm-4.4.0" = "sha256-pZvbah5n9uv/Zkfnp/vrZyRH9tSdPovovK43T8Fu5nM=";
    };
  };
  nativeBuildInputs = [
    libclang
    llvmPackages.bintools
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
