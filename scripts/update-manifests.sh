#!/usr/bin/env bash
# Refresh manifests/{leo,snarkos}-bin.toml with every stable upstream release
# we know how to handle. Wraps update-bin-manifest, which must be on PATH.
#
# Filter rules:
#   leo:     tags matching `leo-lang-vX.Y.Z` (the post-v4.1 split-crate format).
#            Earlier single-tag releases shipped no `leo-release.toml` and a
#            different archive layout.
#   snarkos: tags matching `vX.Y.Z` with major >= 4. Earlier versions ship
#            different runtime deps (the v2.x line uses a separate
#            `aleo-testnet1-*` asset prefix entirely), and we don't try to
#            paper over those differences in a single derivation.
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

# Iterate $1=project tags from stdin, calling update-bin-manifest per version.
# Per-version failures are reported but don't abort the whole run.
import_versions() {
  local project="$1"
  local v inner_args=()
  [ "$force" -eq 1 ] && inner_args+=("--force")
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    echo "--- $project $v ---"
    if ! update-bin-manifest "${inner_args[@]}" "$project" "$v"; then
      echo "  skipping $project $v (no recognised targets or other error)" >&2
    fi
  done
}

# Drop entries from the manifest whose version key is not in $2 (a JSON array
# of versions-to-keep). Re-computes `latest` after pruning so it always points
# at the highest-semver kept version.
prune_manifest() {
  local project="$1"
  local keep_json="$2"
  local manifest_path="$repo_root/manifests/${project}-bin.toml"
  [ -s "$manifest_path" ] || return 0
  local state pruned latest out
  state="$(yj -tj < "$manifest_path")"
  pruned="$(jq --argjson keep "$keep_json" '
    .versions = (.versions // {} | with_entries(select(.key as $k | $keep | index($k))))
  ' <<<"$state")"
  latest="$(jq -r '.versions | keys[]' <<<"$pruned" | sort -V | tail -n1)"
  [ -n "$latest" ] || { echo "$project: pruning emptied the manifest, leaving file untouched" >&2; return 0; }
  pruned="$(jq --arg l "$latest" '. + {latest: $l}' <<<"$pruned")"
  out="$(jq -S . <<<"$pruned" | yj -jt)"
  local tmp
  tmp="$(mktemp "${manifest_path}.XXXXXX")"
  printf '%s\n' "$out" > "$tmp"
  mv "$tmp" "$manifest_path"
}

versions_to_json() {
  jq -R . | jq -s 'map(select(length > 0))'
}

echo "==> leo"
leo_versions="$(
  list_stable_tags ProvableHQ/leo \
    | sed -nE 's/^leo-lang-v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' \
    | sort -V -u
)"
printf '%s\n' "$leo_versions" | import_versions leo
prune_manifest leo "$(printf '%s\n' "$leo_versions" | versions_to_json)"

echo "==> snarkos"
snarkos_versions="$(
  list_stable_tags ProvableHQ/snarkOS \
    | sed -nE 's/^v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' \
    | awk -F. '$1 >= 4 { print }' \
    | sort -V -u
)"
printf '%s\n' "$snarkos_versions" | import_versions snarkos
prune_manifest snarkos "$(printf '%s\n' "$snarkos_versions" | versions_to_json)"

echo "done"
