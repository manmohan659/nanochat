#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
"$root/services/frontend/node_modules/.bin/tsc" "$root/services/frontend/lib/session-request.ts" --target ES2022 --module commonjs --skipLibCheck --outDir "$build_dir"
node "$root/scripts/test_session_request.cjs" "$build_dir/session-request.js"
