#!/usr/bin/env bash
# Refresh manifests/{leo,snarkos}-bin.toml with every stable upstream release
# we know how to handle. Wraps update-bin-manifest, which must be on PATH.
#
# Filter rules:
#   leo-lang : tags matching `leo-lang-vX.Y.Z` (the post-v4.1 split-crate format).
#   leo-fmt  : tags matching `leo-fmt-vX.Y.Z`.
#   leo-lsp  : tags matching `leo-lsp-vX.Y.Z`. Includes pre-toml releases like
#              `leo-lsp-v4.0.2`; those entries simply omit the `compat` table.
#   snarkos  : tags matching `vX.Y.Z` with major >= 4. Earlier versions ship
#              different runtime deps (the v2.x line uses a separate
#              `aleo-testnet1-*` asset prefix entirely), and we don't try to
#              paper over those differences in a single derivation.
#
# The combined `leo-bin.${leo-lang-version}` derivation resolves which plugin
# versions to bundle by reading each plugin release's `compat.leo-lang` and
# picking the latest version that matches (falling back to the leo-lang
# release's own `leo-release.toml` pin). This means leaving older plugin
# releases in the manifest costs nothing — they're addressable as
# `leo-lsp-bin."4.0.2"` but won't accidentally land in any combined bundle.
#
# Caching: entries already present in the manifest are reused without
# re-prefetching. Pass `--force` to ignore the cache. Versions no longer
# matching the filter (or removed upstream) are pruned at the end of each
# project's import loop, so the manifest stays authoritative.
#
# Set GITHUB_TOKEN to authenticate API calls and raise the rate limit (60/hr
# anon, 5000/hr authenticated).
#
# Usage:
#   update-manifests [--force]

set -euo pipefail

force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for cmd in curl jq yj update-bin-manifest; do
  command -v "$cmd" >/dev/null || { echo "required tool missing: $cmd" >&2; exit 1; }
done

if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  repo_root="$PWD"
fi

api() {
  local path="$1"
  local args=(-fsSL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  curl "${args[@]}" "https://api.github.com$path"
}

# Print every stable release tag for $1=owner/repo, one per line.
list_stable_tags() {
  local repo="$1"
  local page=1 chunk count
  while :; do
    chunk="$(api "/repos/$repo/releases?per_page=100&page=$page")"
    count="$(jq -r 'length' <<<"$chunk")"
    [ "$count" -gt 0 ] || break
    jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name' <<<"$chunk"
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
  done
}

# Iterate $1=component tags from stdin, calling update-bin-manifest per version.
# Per-version failures are reported but don't abort the whole run.
import_versions() {
  local component="$1"
  local v inner_args=()
  [ "$force" -eq 1 ] && inner_args+=("--force")
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    echo "--- $component $v ---"
    if ! update-bin-manifest "${inner_args[@]}" "$component" "$v"; then
      echo "  skipping $component $v (no recognised targets or other error)" >&2
    fi
  done
}

# Drop snarkos version entries not in $2 (JSON array of versions-to-keep).
# Recomputes the top-level `latest` string after pruning.
prune_snarkos_manifest() {
  local keep_json="$1"
  local manifest_path="$repo_root/manifests/snarkos-bin.toml"
  [ -s "$manifest_path" ] || return 0
  local state pruned latest out
  state="$(yj -tj < "$manifest_path")"
  pruned="$(jq --argjson keep "$keep_json" '
    .versions = (.versions // {} | with_entries(select(.key as $k | $keep | index($k))))
  ' <<<"$state")"
  latest="$(jq -r '.versions | keys[]' <<<"$pruned" | sort -V | tail -n1)"
  [ -n "$latest" ] || { echo "snarkos: pruning emptied the manifest, leaving file untouched" >&2; return 0; }
  pruned="$(jq --arg l "$latest" '. + {latest: $l}' <<<"$pruned")"
  out="$(jq -S . <<<"$pruned" | yj -jt)"
  local tmp
  tmp="$(mktemp "${manifest_path}.XXXXXX")"
  printf '%s\n' "$out" > "$tmp"
  mv "$tmp" "$manifest_path"
}

# Drop version entries from a single leo component not in $2 (JSON array).
# Recomputes `latest.<component>` from the kept versions; removes the
# component entirely if its kept set is empty.
prune_leo_component() {
  local component="$1"
  local keep_json="$2"
  local manifest_path="$repo_root/manifests/leo-bin.toml"
  [ -s "$manifest_path" ] || return 0
  local state pruned out
  state="$(yj -tj < "$manifest_path")"
  pruned="$(jq --arg c "$component" --argjson keep "$keep_json" '
      if (.components // {}) | has($c) then
        .components[$c].versions = (.components[$c].versions | with_entries(select(.key as $k | $keep | index($k))))
        | if (.components[$c].versions | length) == 0 then
            del(.components[$c])
            | .latest //= {}
            | del(.latest[$c])
          else
            .latest //= {}
            | .latest[$c] = (.components[$c].versions | keys | sort_by(split(".") | map(tonumber)) | last)
          end
      else . end
    ' <<<"$state")"
  out="$(jq -S . <<<"$pruned" | yj -jt)"
  local tmp
  tmp="$(mktemp "${manifest_path}.XXXXXX")"
  printf '%s\n' "$out" > "$tmp"
  mv "$tmp" "$manifest_path"
}

versions_to_json() {
  jq -R . | jq -s 'map(select(length > 0))'
}

run_leo_component() {
  local component="$1" prefix="$2"
  echo "==> $component"
  local vers
  vers="$(
    list_stable_tags ProvableHQ/leo \
      | sed -nE "s/^${prefix}-v([0-9]+\\.[0-9]+\\.[0-9]+)\$/\\1/p" \
      | sort -V -u
  )"
  printf '%s\n' "$vers" | import_versions "$component"
  prune_leo_component "$component" "$(printf '%s\n' "$vers" | versions_to_json)"
}

run_leo_component leo-lang leo-lang
run_leo_component leo-fmt  leo-fmt
run_leo_component leo-lsp  leo-lsp

echo "==> snarkos"
snarkos_versions="$(
  list_stable_tags ProvableHQ/snarkOS \
    | sed -nE 's/^v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' \
    | awk -F. '$1 >= 4 { print }' \
    | sort -V -u
)"
printf '%s\n' "$snarkos_versions" | import_versions snarkos
prune_snarkos_manifest "$(printf '%s\n' "$snarkos_versions" | versions_to_json)"

echo "done"
