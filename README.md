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

### Refreshing the manifest

Manifests live at `manifests/{leo,snarkos}-bin.toml` and are regenerated
by helper scripts that prefetch every (component, target) archive and
record its SRI hash.

To pull in every available upstream stable release in one go:

```console
nix run .#update-manifests           # cached: skips entries already recorded
nix run .#update-manifests -- --force  # re-hashes every (component, target)
```

This enumerates GitHub releases, keeps the tags we know how to handle
(`leo-lang-vX.Y.Z` for leo, `vX.Y.Z` with major ≥ 4 for snarkOS), and
imports each version. Entries already present in the manifest are
reused without re-downloading; use `--force` if upstream re-issued an
archive under the same tag. Versions that no longer match the filter
(or that upstream deleted) are pruned at the end of each project's
import loop. Set `GITHUB_TOKEN` to authenticate API calls if you hit
the anonymous rate limit.

To target a single version:

```console
nix run .#update-bin-manifest --         leo     4.1.0
nix run .#update-bin-manifest -- --force snarkos 4.7.2
```

Re-running either command on an already-recorded version is a no-op —
the manifest pair stays byte-identical. The `latest` pointer is set to
the highest recorded semver. Targets that upstream didn't publish for
a given release (e.g. `x86_64-apple-darwin` on snarkOS v4.7.x) are
skipped with a warning and simply omitted from that version's entry.

## Developing leo

If you're working on the leo repo itself, the following command can be
useful. It allows you to enter a development shell with all of the necessary
dependencies and environment variables to build leo and run the tests. This
includes snarkos (with testnet enabled), openssl and pkg-config.

```console
nix develop github:provablehq/leo.nix
```
