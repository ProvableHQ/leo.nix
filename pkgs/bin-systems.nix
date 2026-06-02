# Maps Nix system identifiers to the upstream target triples used by Leo and
# snarkOS release archives. Systems absent from this set have no upstream binary
# and must fall back to the source-built derivations.
{
  x86_64-linux = "x86_64-unknown-linux-gnu";
  x86_64-darwin = "x86_64-apple-darwin";
  aarch64-darwin = "aarch64-apple-darwin";
}
