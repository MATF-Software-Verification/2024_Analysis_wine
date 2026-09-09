#!/usr/bin/env bash
#
# Pokrece jedan Wine test suite pod Valgrind Memcheck-om.
# Neophodno imati `valgrind` i kompajlovani Wine, bilo putem
# nix-shell ili nekako drugacije.

set -e # Prekidamo izvrsavanje cim neka komanda vrati gresku

# Trenutno fiksiramo modul, test i arhitekturu
MODULE=advapi32
TEST=cred
ARCH=x86_64-windows

# Skripta je u valgrind/memcheck/, $0 ce nam dati "valgrind/memcheck",
# pwd ce dati apsolutnu putanju toga.
LOGDIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$LOGDIR/../.." && pwd)"

export WINESRC="$REPO_ROOT/wine"
export WINEPREFIX="$REPO_ROOT/../myprefix"

# Bez ovoga bi prvi start trazio da radimo nesto sa Wine Mono i Wine Gecko, a to nam je
# nepotrebno tokom pravljenja prefiksa.
export WINEDLLOVERRIDES="mscoree,mshtml="

# vg-wrapper.sh koristi ${WINETEST_WRAPPER:-/opt/valgrind/bin/valgrind},
# pa mu damo pravu putanju pre sourceovanja.
export WINETEST_WRAPPER="$(command -v valgrind)"

# Postavlja VALGRIND_OPTS, WINE, WINESERVER, OANOCACHE i ostalo.
. "$WINESRC/tools/valgrind/vg-wrapper.sh"

# Prefiks se pravi jednom, van Valgrinda.
# Ako ga nema, wineboot ce ga napraviti.
[ -d "$WINEPREFIX" ] || "$WINESRC/wine" wineboot

# wineserver mora da radi van Valgrinda, inace ga Valgrind instrumentuje.
pgrep -f winemine >/dev/null || "$WINESRC/wine" start /min winemine >/dev/null 2>&1

cd "$WINESRC/dlls/$MODULE/tests"
rm -f "$ARCH/$TEST.ok"
make "$ARCH/$TEST.ok" 2>&1 | tee "$LOGDIR/$MODULE-$TEST-$ARCH.log"


