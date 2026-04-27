#!/usr/bin/env bash
# Regenerate pre-built shell completions. Run after changing CLI options in EntryPoint.swift.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release 2>&1
BIN=.build/release/swiftkhd

mkdir -p completions
"$BIN" --generate-completion-script bash > completions/swiftkhd.bash
"$BIN" --generate-completion-script fish > completions/swiftkhd.fish

echo "Completions written to completions/"
