#!/usr/bin/env bash
# Update manifests/<project>-bin.toml with hashes for a released version of leo or snarkos.
#
# Idempotent: re-running for an already-recorded (project, version) pair must produce
# a byte-identical manifest file. The script uses jq -S to enforce sorted keys, and
# yj -jt for TOML rendering (which preserves input key order, so the sorted JSON
# becomes a sorted TOML).
#
# Usage:
#   update-bin-manifest <leo|snarkos> <version>
#
# Examples:
#   update-bin-manifest leo 4.1.0
#   update-bin-manifest snarkos 4.7.2

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: update-bin-manifest <project> <version>
  project: leo | snarkos
  version: a published release version, e.g. 4.1.0
EOF
  exit 2
}

[ $# -eq 2 ] || usage
project="$1"
version="$2"

case "$project" in
  leo|snarkos) ;;
  *) echo "unknown project: $project" >&2; usage ;;
esac

for cmd in curl jq yj nix; do
  command -v "$cmd" >/dev/null || { echo "required tool missing: $cmd" >&2; exit 1; }
done

# Resolve the repo root so this script works both when run directly from a
# checkout and when invoked via `nix run .#update-bin-manifest`.
if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  repo_root="$PWD"
fi
manifest_path="$repo_root/manifests/${project}-bin.toml"
mkdir -p "$(dirname "$manifest_path")"

# Read existing manifest as JSON (empty object if absent or empty).
if [ -s "$manifest_path" ]; then
  state="$(yj -tj < "$manifest_path")"
else
  state="{}"
fi

# Print the SRI hash of the file at $1. Fails loudly on any HTTP/network error.
prefetch_hash() {
  local url="$1"
  echo "  prefetching $url" >&2
  nix store prefetch-file --json "$url" | jq -r .hash
}

# Build a fragment of the form `{versions: {<version>: {...}}}` for leo.
build_leo_fragment() {
  local toml_url="https://github.com/ProvableHQ/leo/releases/download/leo-lang-v${version}/leo-release.toml"
  echo "fetching $toml_url" >&2
  local release_toml release_json
  release_toml="$(curl -fsSL "$toml_url")"
  release_json="$(printf '%s' "$release_toml" | yj -tj)"

  # Targets we map to Nix host platforms; everything else (musl, windows) is ignored.
  local targets='["x86_64-unknown-linux-gnu","x86_64-apple-darwin","aarch64-apple-darwin"]'

  local components='{}'
  while IFS= read -r component; do
    # Only emit components that actually ship a downloadable archive.
    # The leo-release.toml also references crate-only deps (e.g. snarkvm) which we skip.
    local template
    template="$(jq -r --arg c "$component" '.components[$c].archive_url_template // ""' <<<"$release_json")"
    [ -n "$template" ] || continue
    # Only ship the components we expose via leo-bin.{cli,fmt,lsp}.
    case "$component" in
      leo-lang|leo-fmt|leo-lsp) ;;
      *) continue ;;
    esac

    local tag binaries
    tag="$(jq -r --arg c "$component" '.components[$c].tag' <<<"$release_json")"
    binaries="$(jq --arg c "$component" '.components[$c].binaries' <<<"$release_json")"

    local targets_obj='{}'
    while IFS= read -r target; do
      local url="${template//\{target\}/$target}"
      local hash
      hash="$(prefetch_hash "$url")"
      targets_obj="$(jq --arg t "$target" --arg h "$hash" '. + {($t): $h}' <<<"$targets_obj")"
    done < <(jq -r '.[]' <<<"$targets")

    local component_obj
    component_obj="$(jq -n \
      --arg tag "$tag" \
      --argjson binaries "$binaries" \
      --arg template "$template" \
      --argjson targets "$targets_obj" \
      '{archive_url_template: $template, binaries: $binaries, tag: $tag, targets: $targets}')"
    components="$(jq --arg c "$component" --argjson v "$component_obj" '. + {($c): $v}' <<<"$components")"
  done < <(jq -r '.components | keys[]' <<<"$release_json")

  jq -n --arg ver "$version" --argjson components "$components" \
    '{versions: {($ver): {components: $components}}}'
}

# Build a fragment of the form `{versions: {<version>: {...}}}` for snarkos.
build_snarkos_fragment() {
  local tag="v${version}"
  local template="https://github.com/ProvableHQ/snarkOS/releases/download/${tag}/aleo-${tag}-{target}.zip"
  local targets='["x86_64-unknown-linux-gnu","aarch64-apple-darwin"]'

  local targets_obj='{}'
  while IFS= read -r target; do
    local url="${template//\{target\}/$target}"
    local hash
    hash="$(prefetch_hash "$url")"
    targets_obj="$(jq --arg t "$target" --arg h "$hash" '. + {($t): $h}' <<<"$targets_obj")"
  done < <(jq -r '.[]' <<<"$targets")

  jq -n --arg ver "$version" --arg tag "$tag" --arg template "$template" \
        --argjson targets "$targets_obj" \
    '{versions: {($ver): {archive_url_template: $template, binary: "snarkos", tag: $tag, targets: $targets}}}'
}

case "$project" in
  leo)     fragment="$(build_leo_fragment)" ;;
  snarkos) fragment="$(build_snarkos_fragment)" ;;
esac

# Replace (don't deep-merge) the per-version entry: we always recompute the full
# set of targets, so stale entries from a previous schema should not linger.
merged="$(jq --argjson f "$fragment" '
    .versions = ((.versions // {}) + $f.versions)
  ' <<<"$state")"

# `latest` is the semver-max of all version keys after the merge. This avoids
# regressing `latest` when back-filling an older version.
latest="$(jq -r '.versions | keys[]' <<<"$merged" | sort -V | tail -n1)"
merged="$(jq --arg l "$latest" '. + {latest: $l}' <<<"$merged")"

# Canonicalise: sorted keys throughout, then render to TOML.
out="$(jq -S . <<<"$merged" | yj -jt)"

tmp="$(mktemp "${manifest_path}.XXXXXX")"
printf '%s\n' "$out" > "$tmp"
mv "$tmp" "$manifest_path"

echo "wrote $manifest_path (latest=$latest)"
