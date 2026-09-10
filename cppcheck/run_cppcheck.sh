#!/usr/bin/env bash

set -e

command -v cppcheck >/dev/null || { echo "Cppcheck nije u PATH-u, neophodno je dodati ga ili ući u nix shell."; exit 1; }

# Analiziracemo samo Unix stranu ntdll-a
SCOPE='dlls/ntdll/unix/*'
NAME=cppcheck-ntdll-unix

OUTDIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$OUTDIR/.." && pwd)"
WINESRC="$REPO_ROOT/wine"

cd "$WINESRC"

# Generisemo compile_commands.json
make depend

# Pokrecemo cppcheck
cppcheck \
    --project=compile_commands.json \
    --file-filter="$SCOPE" \
    --enable=warning,style,performance,portability \
    -D__x86_64__ -Dlinux \
    --platform=unix64 \
    -j"$(nproc)" \
    --xml --xml-version=2 \
    2> "$OUTDIR/$NAME.xml"

# Generisemo html izvestaj
cppcheck-htmlreport \
    --file="$OUTDIR/$NAME.xml" \
    --report-dir="$OUTDIR/html" \
    --source-dir=.

echo "Cppcheck završen."
