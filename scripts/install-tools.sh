#!/usr/bin/env bash
# Downloads pinned Roblox dev tools into ./.tools (project-local, no sudo, no global install).
# Linux x86_64 only. On Windows use Rokit instead (see docs/TESTING.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.tools/bin"
TMP="$ROOT/.tools/tmp"
mkdir -p "$BIN" "$TMP"

fetch() { # name url
	local name="$1" url="$2"
	if [[ -x "$BIN/$name" ]]; then
		echo "✓ $name already installed"
		return
	fi
	echo "↓ $name"
	curl -fsSL "$url" -o "$TMP/$name.zip"
	unzip -oq "$TMP/$name.zip" -d "$TMP/$name"
	find "$TMP/$name" -type f -name "$name" -exec mv {} "$BIN/$name" \;
	chmod +x "$BIN/$name"
}

fetch rojo     "https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip"
fetch selene   "https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-linux.zip"
fetch stylua   "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-linux-x86_64.zip"
fetch luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip"
fetch lune     "https://github.com/lune-org/lune/releases/download/v0.11.1/lune-0.11.1-linux-x86_64.zip"

# Roblox API type definitions for luau-lsp analyze.
if [[ ! -f "$ROOT/.tools/globalTypes.d.luau" ]]; then
	echo "↓ Roblox type definitions"
	curl -fsSL "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau" \
		-o "$ROOT/.tools/globalTypes.d.luau"
fi

rm -rf "$TMP"
echo "Tools ready in $BIN"
