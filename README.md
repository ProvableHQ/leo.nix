# leo.nix

A Nix flake for the Leo language.

*Supports Linux. MacOS supported, but untested currently.*

## Usage

1. Install Nix, easiest with the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer).

2. Use Nix to enter a shell with the `leo` CLI:

   ```console
   nix shell github:provablehq/leo.nix
   ```

3. Check that it works with:
   ```console
   leo -h
   ```

## Prebuilt binaries

The `leo-bin` and `snarkos-bin` packages skip the from-source build and
fetch the upstream release archives directly. Useful when you just want to
run a specific released version without waiting for `cargo`.

```console
# Latest stable, combined leo CLI plus first-party plugins:
nix shell github:provablehq/leo.nix#leo-bin

# A pinned version (any version recorded in `manifests/leo-bin.toml`):
nix shell 'github:provablehq/leo.nix#leo-bin."4.1.0"'

# Individual components:
nix shell github:provablehq/leo.nix#leo-cli-bin
nix shell github:provablehq/leo.nix#leo-fmt-bin
nix shell github:provablehq/leo.nix#leo-lsp-bin

# snarkOS:
nix shell github:provablehq/leo.nix#snarkos-bin
nix shell 'github:provablehq/leo.nix#snarkos-bin."4.7.2"'
```

Supported targets: `x86_64-linux` (leo, snarkos), `x86_64-darwin` (leo),
`aarch64-darwin` (leo, snarkos). On systems with no upstream binary
(`aarch64-linux`), use the from-source `leo` and `snarkos` packages instead.

### Adding a new version

Manifests live at `manifests/{leo,snarkos}-bin.toml` and are regenerated
by a small script that prefetches every (component, target) archive and
records its SRI hash:

```console
nix run .#update-bin-manifest -- leo     4.1.0
nix run .#update-bin-manifest -- snarkos 4.7.2
```

Re-running the script for an already-recorded version is a no-op — it
should produce a byte-identical manifest. The `latest` pointer is bumped
to the highest recorded semver.

## Developing leo

If you're working on the leo repo itself, the following command can be
useful. It allows you to enter a development shell with all of the necessary
dependencies and environment variables to build leo and run the tests. This
includes snarkos (with testnet enabled), openssl and pkg-config.

```console
nix develop github:provablehq/leo.nix
```
