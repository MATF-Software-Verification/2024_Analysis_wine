#!/usr/bin/env bash

set -e # Prekidamo izvrsavanje cim neka komanda vrati gresku

# Trenutno fiksiramo modul, test i arhitekturu
MODULE=advapi32
TEST=cred
ARCH=x86_64-windows

# Skripta je u ubsan/, koren repozitorijuma je nivo iznad.
OUTDIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$OUTDIR/.." && pwd)"
WINESRC="$REPO_ROOT/wine"

export WINEPREFIX="$REPO_ROOT/../myprefix"
export WINEDLLOVERRIDES="mscoree,mshtml="

# Logovi se imenuju po PID-u, pa bi se stari pomesali sa novim.
rm -f "$OUTDIR"/ubsan.*

# Gasimo ako postoji vec neki wineserver od prethodnog tesitranja
"$WINESRC/server/wineserver" -k >/dev/null 2>&1 || true
"$WINESRC/wine" wineboot -u >/dev/null 2>&1

# halt_on_error=0 znaci da se izvrsavanje nastavlja posle prijave, pa se u
# jednom prolazu prikupe sve. log_path pravi po jedan fajl po procesu, jer
# jedno pokretanje testa podigne vise Wine procesa nad istim ntdll.so.
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0:log_path=$OUTDIR/ubsan"

cd "$WINESRC/dlls/$MODULE/tests"
rm -f "$ARCH/$TEST.ok"
make "$ARCH/$TEST.ok" 2>&1 | tee "$OUTDIR/$MODULE-$TEST-$ARCH.log"

echo
echo "Prijave po mestu u kodu:"
cat "$OUTDIR"/ubsan.* 2>/dev/null | grep "runtime error" 
