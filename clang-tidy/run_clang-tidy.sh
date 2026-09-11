#!/usr/bin/env bash
#
# Pokrece clang-tidy nad Unix stranom ntdll-a.
# Neophodni su `clang-tidy` i vec preveden Wine (zbog compile_commands.json).

set -e

command -v clang-tidy >/dev/null || { echo "clang-tidy nije u PATH-u, potrebno je instalirati ga ili ući u nix-shell"; exit 1; }

# Kao i do sad, analiziramo unix stranu ntdll-a.
SCOPE='dlls/ntdll/unix/*.c'
NAME=clang-tidy-ntdll-unix

CHECKS='-*,bugprone-*,clang-analyzer-*,-bugprone-easily-swappable-parameters,-bugprone-narrowing-conversions,-bugprone-assignment-in-if-condition,-bugprone-suspicious-string-compare,-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling,-clang-analyzer-security.insecureAPI.strcpy'

# Skripta je u clang-tidy/, koren repozitorijuma je nivo iznad.
OUTDIR="$(cd "$(dirname "$0")" && pwd)"
WINESRC="$(cd "$OUTDIR/.." && pwd)/wine"


# Specificno za NixOS, CPATH cemo definisati kako se Clang Static Analyzer ne bi bunio.
# On ce pomoci Clang Static Analyzer-u da nadje header fajlove za glibc i valgrind.
# Bez toga, on prijavljuje gresku...
if [ -n "$VS_CLANG_CPATH" ]; then
    export CPATH="$VS_CLANG_CPATH"
fi

cd "$WINESRC"

# Generisemo compile_commands.json
make depend

# clang-tidy vraca nenultu vrednost kad nadje nalaze, a to nije greska za nas pa dodajemo || true,
# kako set -e ne bi prekinuo skriptu.
clang-tidy -p . --checks="$CHECKS" $SCOPE > "$OUTDIR/$NAME.txt" 2>&1 || true

echo "Gotovo: $OUTDIR/$NAME.txt"


