{
  leo,
  mkShell,
  snarkos-testnet,
}:
mkShell {
  inputsFrom = [
    leo
  ];
  buildInputs = [
    snarkos-testnet
  ];
}
