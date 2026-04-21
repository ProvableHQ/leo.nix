{
  cargo-nextest,
  leo-cli,
  leo-fmt,
  mkShell,
  rust-bin,
  snarkos-testnet,
}:
let
  rust-nightly = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
in
mkShell {
  inputsFrom = [
    leo-cli
    leo-fmt
    snarkos-testnet
  ];
  buildInputs = [
    cargo-nextest
    snarkos-testnet
  ];
  env = {
    inherit (snarkos-testnet) ROCKSDB_LIB_DIR;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
