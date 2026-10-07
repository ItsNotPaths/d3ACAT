#!/usr/bin/env bash
# Build a release binary, or ask GitHub to build and publish one.
#
#   ./release.sh --local
#   ./release.sh --public --version 0.1.0 --notes "notes here"
#
# --public builds on GitHub, for Linux and Windows (.github/workflows).
set -euo pipefail
cd "$(dirname "$0")"

WORKFLOW=release.yml

usage() {
    cat >&2 <<'USAGE'
usage: ./release.sh --local
       ./release.sh --public --version <x.y.z> --notes <text>
USAGE
}

die() { echo "$*" >&2; exit 1; }

# A build from edited files is marked, so a dirty tree never claims a clean commit.
build_commit() {
    local id
    id="$(git rev-parse --short HEAD 2>/dev/null)" || { echo unknown; return; }
    [ -z "$(git status --porcelain)" ] || id="$id-dirty"
    echo "$id"
}

build() {
    mkdir -p build
    odin build src/app -o:speed -out:build/d3acat \
        -define:D3ACAT_VERSION="_${1:-dev}" \
        -define:D3ACAT_COMMIT="_$(build_commit)"
}

[ "$#" -ge 1 ] || { usage; exit 2; }
mode="$1"; shift

case "$mode" in
    --local)
        [ "$#" -eq 0 ] || { usage; exit 2; }
        build dev
        ./build/d3acat --version
        ;;
    --public)
        version=""
        notes=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --version) [ "$#" -ge 2 ] || die "--version needs a number"; version="$2"; shift 2 ;;
                --notes)   [ "$#" -ge 2 ] || die "--notes needs text";      notes="$2";   shift 2 ;;
                *) usage; exit 2 ;;
            esac
        done
        [ -n "$version" ] && [ -n "$notes" ] || { usage; exit 2; }
        [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version wants x.y.z, got $version"

        command -v gh >/dev/null || die "gh is not installed"
        gh auth status >/dev/null 2>&1 || die "gh is not logged in; run: gh auth login"
        [ -z "$(git status --porcelain)" ] || die "the working tree is dirty; commit first"
        gh release view "v$version" >/dev/null 2>&1 && die "v$version is already released"

        head="$(git rev-parse HEAD)"
        git fetch -q origin
        git merge-base --is-ancestor "$head" origin/main \
            || die "HEAD is not pushed; the workflow builds what is on origin"

        echo "releasing v$version from ${head:0:8}"
        gh workflow run "$WORKFLOW" -f version="$version" -f notes="$notes"
        echo "watch it: gh run watch"
        ;;
    *)
        usage; exit 2 ;;
esac
