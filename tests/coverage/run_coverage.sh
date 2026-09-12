#!/usr/bin/env bash
set -e 

OUTDIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$OUTDIR/../.." && pwd)"
WINESRC="$REPO_ROOT/wine"

RESULTS="$OUTDIR/results"

# Krecemo od cistog Makefile.in-a, da ne bi imali konflikt ako smo pokretali UBSan patch pre toga.
git -C "$WINESRC" checkout dlls/ntdll/Makefile.in
git -C "$WINESRC" apply "$REPO_ROOT/custom-gcov.patch"

cd "$WINESRC"
make depend
rm -f dlls/ntdll/unix/*.o dlls/ntdll/unix/*.gcda
make -j"$(nproc)"

bash "$REPO_ROOT/tests/run_tests.sh"

# .gcda se upisuje tek kad proces uredno izadje, pa cekamo pomocne procese.
# Namerno -w a ne -k, jer -k ih ubija i brojaci se gube.
"$WINESRC/server/wineserver" -w

rm -rf "$RESULTS" && mkdir -p "$RESULTS"

# gcov mora da se pokrene iz korena Wine stabla, jer su putanje u .gcno
# zapisane relativno u odnosu na njega. Rezultate posle premestamo.
cd "$WINESRC"
gcov -o dlls/ntdll/unix dlls/ntdll/unix/*.c > "$RESULTS/summary.txt" 2>&1
mv "$WINESRC"/*.gcov "$RESULTS/"

echo
echo "Pokrivenost po fajlu:"
grep -B1 "^Lines executed" "$RESULTS/summary.txt" \
    | grep -v '^--$' \
    | paste - - \
    | grep "ntdll/unix/.*\.c'" \
    | sed "s|.*unix/||;s|'||"
echo
echo "Ukupno: $(tail -1 "$RESULTS/summary.txt")"
echo "Detalji: $RESULTS/*.gcov"


