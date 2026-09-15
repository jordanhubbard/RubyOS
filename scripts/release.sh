#!/usr/bin/env bash
# Publish a RubyOS release only after local validation and green Linux/macOS CI.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

info() { printf '[release] %s\n' "$*"; }
fail() { printf '[release] ERROR: %s\n' "$*" >&2; exit 1; }

current_version() {
    git tag -l 'v[0-9]*' --sort=-v:refname | sed -n '1{s/^v//;p;}'
}

next_version() {
    local current="$1" request="$2" major minor patch
    if [[ "$request" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s\n' "${request#v}"
        return
    fi
    [[ "$request" =~ ^(major|minor|patch)$ ]] || fail "use major, minor, patch, or X.Y.Z"
    IFS=. read -r major minor patch <<<"$current"
    case "$request" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
    esac
    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

wait_for_ci() {
    local sha="$1" run_id=""
    info "waiting for Linux and macOS CI at $sha"
    for _ in $(seq 1 90); do
        run_id="$(gh run list --workflow CI --branch main --limit 20 \
            --json databaseId,headSha \
            --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -1)"
        if [[ -n "$run_id" ]]; then
            gh run watch "$run_id" --exit-status || return $?
            printf '%s\n' "$run_id"
            return
        fi
        sleep 10
    done
    fail "no CI run appeared for $sha"
}

request="${1:-patch}"
previous="$(current_version)"
[[ -n "$previous" ]] || previous=0.0.0
version="$(next_version "$previous" "$request")"
tag="v$version"
source_version="$(sed -n 's/^  VERSION = "\([^"]*\)"/\1/p' kernel/rubyos.rb)"

command -v gh >/dev/null || fail "GitHub CLI is required"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated"
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || fail "release must run on main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
git rev-parse "$tag" >/dev/null 2>&1 && fail "$tag already exists"
[[ "$source_version" == "$version" ]] || fail "kernel version is $source_version, expected $version"
grep -Fq "# RubyOS $tag" RELEASE-NOTES.md || fail "RELEASE-NOTES.md is not for $tag"

info "running local release validation"
./scripts/validate-release.sh
info "syncing and pushing main"
git pull --rebase origin main
git push origin main
sha="$(git rev-parse HEAD)"
run_id="$(wait_for_ci "$sha" | tail -1)"

assets="$(mktemp -d "${TMPDIR:-/tmp}/rubyos-assets.XXXXXX")"
notes="$(mktemp "${TMPDIR:-/tmp}/rubyos-notes.XXXXXX")"
trap 'rm -rf "$assets"; rm -f "$notes"' EXIT
gh run download "$run_id" --name rubyos-linux --dir "$assets/linux"
gh run download "$run_id" --name rubyos-macos --dir "$assets/macos"
mapfile -t archives < <(find "$assets" -name '*.tar.gz' -type f | sort)
mapfile -t checksums < <(find "$assets" -name '*.sha256' -type f | sort)
[[ ${#archives[@]} -eq 2 && ${#checksums[@]} -eq 2 ]] || fail "CI did not produce both platform bundles"
for checksum in "${checksums[@]}"; do
    (cd "$(dirname "$checksum")" && sha256sum -c "$(basename "$checksum")")
done

{
    cat RELEASE-NOTES.md
    printf '\n## Release validation\n\n'
    # shellcheck disable=SC2016
    printf -- '- Linux and macOS workflow: `%s`\n' "$run_id"
    # shellcheck disable=SC2016
    printf -- '- Source commit: `%s`\n' "$sha"
} >"$notes"

info "tagging $tag"
git tag -a "$tag" -m "RubyOS $tag"
git push origin "$tag"
info "publishing CI-produced artifacts"
gh release create "$tag" --title "RubyOS $tag" --notes-file "$notes" \
    "${archives[@]}" "${checksums[@]}"
info "release complete: $tag"
