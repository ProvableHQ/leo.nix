{
  cargo-nextest,
  jq,
  leo-cli,
  leo-fmt,
  leo-lsp,
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
    leo-lsp
    snarkos-testnet
  ];
  buildInputs = [
    cargo-nextest
    jq
    snarkos-testnet
  ];
  env = {
    inherit (snarkos-testnet) ROCKSDB_LIB_DIR;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
