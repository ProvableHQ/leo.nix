{
  cargo-nextest,
  mkShell,
  rust-bin,
  snarkos,
}:
let
  rust-nightly = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
in
mkShell {
  inputsFrom = [
    snarkos
  ];
  buildInputs = [
    cargo-nextest
  ];
  env = {
    inherit (snarkos) LIBCLANG_PATH ROCKSDB_LIB_DIR LD_LIBRARY_PATH;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
