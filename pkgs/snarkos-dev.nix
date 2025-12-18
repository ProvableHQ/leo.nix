{
  cargo-nextest,
  mkShell,
  snarkos,
}:
mkShell {
  inputsFrom = [
    snarkos
  ];
  buildInputs = [
    cargo-nextest
  ];
  env = {
    inherit (snarkos) LIBCLANG_PATH;
  };
}
