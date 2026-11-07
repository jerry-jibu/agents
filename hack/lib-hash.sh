#!/usr/bin/env bash
# lib-hash.sh — shared deployedHash baseline algorithm (design S8 pin).
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib-hash.sh"
#
# Deterministic, LOCATION-INDEPENDENT content hash:
#   ( cd <dir> && find . -type f ! -name .DS_Store -print0 |
#     xargs -0 shasum | LC_ALL=C sort | shasum )
# The subshell cd makes shasum emit "./relative" paths, so the hash covers
# content + relative structure only — identical trees at different absolute
# locations (different $HOME, repo vs node, temp sandbox) hash identically.
# Without the cd, shasum's output lines embed absolute paths and the "content"
# hash silently becomes path-dependent (Stage 2 lesson: one temp-HOME sandbox
# run poisoned every baseline in the shared lock). Sorting shasum's output
# lines — not find's NUL stream, since macOS BSD sort has no -z — removes
# dependence on directory-entry order and on xargs batching.
hash_dir() {
  ( cd "$1" 2>/dev/null &&
    find . -type f ! -name .DS_Store -print0 |
    xargs -0 shasum 2>/dev/null | LC_ALL=C sort | shasum | awk '{print $1}'
  )
}
