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
  ];
  buildInputs = [
    snarkos-testnet
  ];
  env = {
    inherit (snarkos-testnet) LIBCLANG_PATH;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
