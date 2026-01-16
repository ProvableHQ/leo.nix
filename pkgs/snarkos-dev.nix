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
    inherit (snarkos) ROCKSDB_LIB_DIR;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
