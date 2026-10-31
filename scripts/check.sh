#!/usr/bin/env bash
# Static checks: formatting, lint, type analysis, and a full Rojo build.
# Usage: scripts/check.sh          everything (about 15 minutes; what CI runs)
#        scripts/check.sh --fast   skips the long simulations (Levels, Players, Properties)
# Run scripts/install-tools.sh once first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/.tools/bin:$PATH"

echo "== StyLua (format check)"
stylua --check src tests tools scripts

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

echo "== Unit, integration and simulated gameplay tests (Lune)"
failed_specs=()
for spec in tests/*.spec.luau; do
	case "${1:-}:$spec" in
	--fast:tests/Levels.spec.luau | --fast:tests/Players.spec.luau | --fast:tests/Properties.spec.luau)
		echo "(skipped by --fast: $spec)"
		continue
		;;
	esac
	# every spec runs even if an earlier one fails, so a failure can't hide later ones
	lune run "$spec" || failed_specs+=("$spec")
done
if ((${#failed_specs[@]} > 0)); then
	echo "FAILED: ${failed_specs[*]}"
	exit 1
fi

echo "== Rojo build"
mkdir -p build
rojo build default.project.json -o build/NightShift.rbxl
rojo build qa.project.json -o build/NightShiftQA.rbxl
echo "All checks passed → build/NightShift.rbxl"
