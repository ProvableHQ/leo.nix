{
  leo,
  mkShell,
  rust-bin,
  snarkos-testnet,
}:
let
  rust-nightly = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
in
mkShell {
  inputsFrom = [
    leo
    snarkos-testnet
  ];
  buildInputs = [
    snarkos-testnet
  ];
  env = {
    inherit (snarkos-testnet) LIBCLANG_PATH ROCKSDB_LIB_DIR;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
