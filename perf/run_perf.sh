#!/usr/bin/env bash
#
# Profilise jedan Wine test suite pomocu perf-a.
# Zahteva Wine preveden bez instrumentacije, sa podrazumevanim -g -O2.

set -e 

MODULE=ntdll
TEST=file
ARCH=x86_64-windows
RUNS=20

OUTDIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$OUTDIR/.." && pwd)"
WINESRC="$REPO_ROOT/wine"

export WINEPREFIX="$REPO_ROOT/../myprefix"
export WINEDEBUG=-all

# Instrumentacija iz UBSan ili gcov analize bi pokvarila merenje, pa preventivno to brisemo
git -C "$WINESRC" checkout dlls/ntdll/Makefile.in
cd "$WINESRC"
make depend
rm -f dlls/ntdll/unix/*.o dlls/ntdll/unix/*.gcda
make -j"$(nproc)"

TESTEXE="dlls/$MODULE/tests/$ARCH/${MODULE}_test.exe"

# Zagrevanje: prvi prolaz podize wineserver i ucitava fontove. Njega ne merimo,
# inace bi u uzorke uslo sve sto se desava samo pri hladnom startu.
# || true jer test vraca nenultu vrednost kad neka provera padne.
./wine "$TESTEXE" "$TEST" >/dev/null 2>&1 || true

perf record -g --call-graph dwarf -o "$OUTDIR/perf.data" -- \
    sh -c "for i in \$(seq $RUNS); do ./wine '$TESTEXE' '$TEST' >/dev/null 2>&1 || true; done"

cd "$OUTDIR"
perf report -i perf.data --stdio --no-children | grep -v '^#' > report-flat.txt
perf report -i perf.data --stdio | grep -v '^#' | head -80 > report-tree.txt

echo
echo "Najskuplje funkcije:"
head -20 report-flat.txt
