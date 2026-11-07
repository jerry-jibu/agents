#!/usr/bin/env bash
# lib-hash.sh — shared deployedHash baseline algorithm (design N1/S8 pin).
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib-hash.sh"
# Algorithm: find <dir> -type f ! -name .DS_Store -print0 | sort -z |
#            xargs -0 shasum | shasum  (sort -z degrades to find order,
#            which is tree-deterministic, when the local sort lacks it).

if sort -z </dev/null >/dev/null 2>&1; then
  hash_dir() {
    find "$1" -type f ! -name .DS_Store -print0 | sort -z |
      xargs -0 shasum 2>/dev/null | shasum | awk '{print $1}'
  }
else
  hash_dir() {
    find "$1" -type f ! -name .DS_Store -print0 |
      xargs -0 shasum 2>/dev/null | shasum | awk '{print $1}'
  }
fi
