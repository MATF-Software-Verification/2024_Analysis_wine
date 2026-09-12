#!/usr/bin/env bash
#
# Ubacuje nase testove u Wine stablo, prevodi ih i pokrece.

set -e 

# Da nam ne smeta wine debug ispis
export WINEDEBUG=-all

MODULE=ntdll
TEST=token
ARCH=x86_64-windows

OUTDIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$OUTDIR/.." && pwd)"
WINESRC="$REPO_ROOT/wine"

export WINEPREFIX="$REPO_ROOT/../myprefix"
export WINEDLLOVERRIDES="mscoree,mshtml="

DEST="$WINESRC/dlls/$MODULE/tests"

cp "$OUTDIR/$TEST.c" "$DEST/"

# Upisujemo token.c u Makefile.in
# Bez ovoga makedep ne zna za nas test i ne upisuje ga u testlist.c.
grep -q "$TEST.c" "$DEST/Makefile.in" || \
    sed -i "s|^\tunwind.c \\\\|\t$TEST.c \\\\\n\tunwind.c \\\\|" "$DEST/Makefile.in"

cd "$WINESRC"
make depend
make -j"$(nproc)" "dlls/$MODULE/tests/all"

./wine "dlls/$MODULE/tests/$ARCH/${MODULE}_test.exe" "$TEST" 2>&1 | tee "$OUTDIR/$TEST-$ARCH.log"


