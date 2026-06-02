#!/usr/bin/env bash
# Update the relevant manifest with hashes for a released version of a leo
# component or snarkos.
#
# Components and where they land:
#   leo-lang | leo-fmt | leo-lsp  → manifests/leo-bin.toml
#                                   (under components.<comp>.versions.<ver>)
#   snarkos                       → manifests/snarkos-bin.toml
#                                   (under versions.<ver>)
#
# For leo components: when the release ships a `leo-release.toml`, the
# co-listed component versions (excluding self) are recorded in a `compat`
# table — that's what the combined `leo-bin` builder uses to resolve which
# plugin versions to bundle with a given leo-lang.
#
# Idempotent: re-running for an already-recorded (component, version) pair
# produces a byte-identical manifest. Cache reuses per-target hashes from
# the existing manifest; pass `--force` to re-prefetch everything.
#
# Usage:
#   update-bin-manifest [--force] <component> <version>
#
# Examples:
#   update-bin-manifest leo-lang 4.1.0
#   update-bin-manifest leo-lsp  4.0.2
#   update-bin-manifest --force snarkos 4.7.2

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: update-bin-manifest [--force] <component> <version>
  --force      ignore the cache; re-prefetch every target asset
  component    leo-lang | leo-fmt | leo-lsp | snarkos
  version      a published release version, e.g. 4.1.0
EOF
  exit 2
}

force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *) break ;;
  esac
done

[ $# -eq 2 ] || usage
component="$1"
version="$2"

case "$component" in
  leo-lang|leo-fmt|leo-lsp) manifest_basename="leo-bin" ;;
  snarkos)                  manifest_basename="snarkos-bin" ;;
  *) echo "unknown component: $component" >&2; usage ;;
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
manifest_path="$repo_root/manifests/${manifest_basename}.toml"
mkdir -p "$(dirname "$manifest_path")"

# Read existing manifest as JSON (empty object if absent or empty).
if [ -s "$manifest_path" ]; then
  state="$(yj -tj < "$manifest_path")"
else
  state="{}"
fi

# Probe a URL and, if present, print its SRI hash. Returns 22 (curl's 404
# exit code) when the asset is missing, so callers can skip silently — that
# happens often when iterating over targets that this particular upstream
# release simply didn't ship. Other errors propagate.
try_prefetch_hash() {
  local url="$1"
  local rc=0
  curl -fsIL -o /dev/null --max-time 30 "$url" || rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  echo "  prefetching $url" >&2
  nix store prefetch-file --json "$url" | jq -r .hash
}

# Iterate `targets` (JSON array) against `template` (with {target}
# placeholder); emit a JSON object of `{target: hash}` for every asset that
# resolves to 200. Missing assets are warned and skipped; other failures abort.
#
# Args: template, targets-json, existing-targets-json
# `existing-targets-json` is the `{target: hash}` from the previous manifest
# state. When `$force` is 0, any target with a non-empty cached hash is used
# as-is, skipping both the HEAD probe and the prefetch.
prefetch_targets() {
  local template="$1"
  local targets_json="$2"
  local existing="${3:-{\}}"
  local out='{}'
  local target url hash cached rc
  while IFS= read -r target; do
    if [ "$force" -eq 0 ]; then
      cached="$(jq -r --arg t "$target" '.[$t] // ""' <<<"$existing")"
      if [ -n "$cached" ]; then
        echo "  - $target: cached ($cached)" >&2
        out="$(jq --arg t "$target" --arg h "$cached" '. + {($t): $h}' <<<"$out")"
        continue
      fi
    fi
    url="${template//\{target\}/$target}"
    set +e
    hash="$(try_prefetch_hash "$url")"
    rc=$?
    set -e
    case "$rc" in
      0)
        out="$(jq --arg t "$target" --arg h "$hash" '. + {($t): $h}' <<<"$out")"
        ;;
      22)
        echo "  - $target: not published for this release, skipping" >&2
        ;;
      *)
        echo "  - $target: prefetch failed (curl exit $rc)" >&2
        return "$rc"
        ;;
    esac
  done < <(jq -r '.[]' <<<"$targets_json")
  printf '%s' "$out"
}

# Build a fragment shaped:
#   {components: {<comp>: {binaries: [...], versions: {<ver>: {...}}}}}
# for one leo-* component release. The version entry has:
#   tag, archive_url_template, targets, and (optionally) compat.
build_leo_component_fragment() {
  local tag="${component}-v${version}"
  local template="https://github.com/ProvableHQ/leo/releases/download/${tag}/${tag}-{target}.zip"
  local targets='["x86_64-unknown-linux-gnu","x86_64-apple-darwin","aarch64-apple-darwin"]'

  # Parse leo-release.toml when present. Pre-v4.1 split-tag releases (e.g.
  # leo-lsp-v4.0.2) don't ship one — those simply omit `compat` from the
  # manifest entry.
  local toml_url="https://github.com/ProvableHQ/leo/releases/download/${tag}/leo-release.toml"
  local compat='{}'
  local release_toml
  if release_toml="$(curl -fsSL --max-time 30 "$toml_url" 2>/dev/null)"; then
    echo "  parsing $toml_url" >&2
    local release_json other other_ver
    release_json="$(printf '%s' "$release_toml" | yj -tj)"
    for other in leo-lang leo-fmt leo-lsp; do
      [ "$other" != "$component" ] || continue
      other_ver="$(jq -r --arg c "$other" '.components[$c].version // ""' <<<"$release_json")"
      [ -n "$other_ver" ] || continue
      compat="$(jq --arg c "$other" --arg v "$other_ver" '. + {($c): $v}' <<<"$compat")"
    done
  else
    echo "  no leo-release.toml at $toml_url (pre-toml release, omitting compat)" >&2
  fi

  local existing_targets targets_obj
  existing_targets="$(jq --arg c "$component" --arg v "$version" \
    '.components[$c].versions[$v].targets // {}' <<<"$state")"
  targets_obj="$(prefetch_targets "$template" "$targets" "$existing_targets")"
  if [ "$(jq 'length' <<<"$targets_obj")" -eq 0 ]; then
    echo "$component $version: no published targets we recognise; aborting" >&2
    return 1
  fi

  local version_obj
  if [ "$(jq 'length' <<<"$compat")" -gt 0 ]; then
    version_obj="$(jq -n \
      --arg tag "$tag" \
      --arg template "$template" \
      --argjson compat "$compat" \
      --argjson targets "$targets_obj" \
      '{archive_url_template: $template, compat: $compat, tag: $tag, targets: $targets}')"
  else
    version_obj="$(jq -n \
      --arg tag "$tag" \
      --arg template "$template" \
      --argjson targets "$targets_obj" \
      '{archive_url_template: $template, tag: $tag, targets: $targets}')"
  fi

  # Binaries are stable per crate; hardcoded.
  local binaries_obj
  case "$component" in
    leo-lang) binaries_obj='["leo"]' ;;
    leo-fmt)  binaries_obj='["leo-fmt"]' ;;
    leo-lsp)  binaries_obj='["leo-lsp"]' ;;
  esac

  jq -n \
    --arg c "$component" \
    --arg v "$version" \
    --argjson binaries "$binaries_obj" \
    --argjson version_obj "$version_obj" \
    '{components: {($c): {binaries: $binaries, versions: {($v): $version_obj}}}}'
}

# Build a fragment shaped `{versions: {<ver>: {...}}}` for snarkos.
build_snarkos_fragment() {
  local tag="v${version}"
  local template="https://github.com/ProvableHQ/snarkOS/releases/download/${tag}/aleo-${tag}-{target}.zip"
  # Include x86_64-apple-darwin: older snarkos releases (≤ v3.x) ship it
  # instead of aarch64-apple-darwin; new releases ship the inverse. Probing
  # both lets one manifest entry serve every recorded version.
  local targets='["x86_64-unknown-linux-gnu","x86_64-apple-darwin","aarch64-apple-darwin"]'

  local existing_targets targets_obj
  existing_targets="$(jq --arg v "$version" '.versions[$v].targets // {}' <<<"$state")"
  targets_obj="$(prefetch_targets "$template" "$targets" "$existing_targets")"
  if [ "$(jq 'length' <<<"$targets_obj")" -eq 0 ]; then
    echo "snarkos $version: no published targets we recognise; aborting" >&2
    return 1
  fi

  jq -n --arg ver "$version" --arg tag "$tag" --arg template "$template" \
        --argjson targets "$targets_obj" \
    '{versions: {($ver): {archive_url_template: $template, binary: "snarkos", tag: $tag, targets: $targets}}}'
}

case "$component" in
  leo-lang|leo-fmt|leo-lsp)
    fragment="$(build_leo_component_fragment)"
    # Merge: keep existing components/versions; replace this component's
    # binaries (always recomputed) and this (component, version) entry.
    merged="$(jq \
        --arg c "$component" --arg v "$version" \
        --argjson f "$fragment" \
        '
          .components = (.components // {})
          | .components[$c] = (.components[$c] // {})
          | .components[$c].binaries = $f.components[$c].binaries
          | .components[$c].versions = (.components[$c].versions // {})
          | .components[$c].versions[$v] = $f.components[$c].versions[$v]
        ' <<<"$state")"
    # latest.<component> = semver-max of all recorded versions for this component.
    latest_for_comp="$(jq -r --arg c "$component" '.components[$c].versions | keys[]' <<<"$merged" \
                       | sort -V | tail -n1)"
    merged="$(jq --arg c "$component" --arg l "$latest_for_comp" \
        '.latest = (.latest // {}) | .latest[$c] = $l' <<<"$merged")"
    echo_latest="$latest_for_comp ($component)"
    ;;
  snarkos)
    fragment="$(build_snarkos_fragment)"
    merged="$(jq --argjson f "$fragment" '.versions = ((.versions // {}) + $f.versions)' <<<"$state")"
    # snarkos manifest has a single top-level `latest` (the schema predates
    # multi-component support; no reason to break compat).
    latest="$(jq -r '.versions | keys[]' <<<"$merged" | sort -V | tail -n1)"
    merged="$(jq --arg l "$latest" '. + {latest: $l}' <<<"$merged")"
    echo_latest="$latest"
    ;;
esac

# Canonicalise: sorted keys throughout, then render to TOML.
out="$(jq -S . <<<"$merged" | yj -jt)"

tmp="$(mktemp "${manifest_path}.XXXXXX")"
printf '%s\n' "$out" > "$tmp"
mv "$tmp" "$manifest_path"

echo "wrote $manifest_path (latest=$echo_latest)"
