{
  cargo-nextest,
  lld,
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
    lld
  ];
  env = {
    inherit (snarkos) LIBCLANG_PATH;
    RUSTFMT = "${rust-nightly}/bin/rustfmt";
  };
}
