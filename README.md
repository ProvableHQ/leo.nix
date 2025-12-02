# leo.nix

A Nix flake for the Leo language.

*Supports Linux & macOS.*

## Usage

1. Install Nix, easiest with the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer).

2. Use Nix to enter a shell with the `leo` CLI:

   ```console
   nix shell github:mitchmindtree/leo.nix
   ```

3. Check that it works with:
   ```console
   leo -h
   ```

## Developing leo

If you're working on the leo repo itself, the following command can be
useful. It allows you to enter a development shell with all of the necessary
dependencies and environment variables to build leo and run the tests. This
includes openssl and pkg-config.

```console
nix develop github:mitchmindtree/leo.nix
```
