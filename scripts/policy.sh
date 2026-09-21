#!/usr/bin/env bash
# Deprecated in v0.5: the routing policy lives in the Orchestra policy. Forwards to `orchestra route`.
[ "${1:-}" = get ] && shift; exec "$(cd "$(dirname "$0")" && pwd)/orchestra" route "$@"
