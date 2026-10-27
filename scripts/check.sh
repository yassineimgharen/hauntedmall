#!/usr/bin/env bash
# Static checks: formatting, lint, type analysis, and a full Rojo build.
# Usage: scripts/check.sh        (run scripts/install-tools.sh once first)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/.tools/bin:$PATH"

echo "== StyLua (format check)"
stylua --check src

echo "== selene (lint)"
selene src

echo "== luau-lsp (type analysis)"
rojo sourcemap default.project.json -o sourcemap.json >/dev/null
out="$(luau-lsp analyze --sourcemap=sourcemap.json --definitions=.tools/globalTypes.d.luau \
	--platform=roblox --flag:LuauSolverV2=false src 2>&1 | grep -E "TypeError|SyntaxError" || true)"
if [[ -n "$out" ]]; then
	echo "$out"
	exit 1
fi
echo "no type errors"

echo "== Unit tests (Lune)"
for spec in tests/*.spec.luau; do
	lune run "$spec"
done

echo "== Rojo build"
mkdir -p build
rojo build default.project.json -o build/NightShift.rbxl
echo "All checks passed → build/NightShift.rbxl"
