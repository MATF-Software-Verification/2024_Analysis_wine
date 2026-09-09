# 2024_Analysis_wine

## Informacije o autoru seminarskog rada

Nikola Kuburović, 1048/2024

## Opis analiziranog projekta

[Wine](https://www.winehq.org/) je reimplementacija Windows API-ja, nije emulator (Wine Is Not an Emulator - WINE).
Wine implementira sopstvene verzije Windows biblioteka (`kernel32.dll`, `user32.dll`, `shlwapi.dll`, `ntdll.dll` …)
u vidu `.c` fajlova, koje se zatim prevode uz pomoć kompajlera u PE format, na mestu gde ih Windows program očekuje.

Mali primer celog procesa:

1) `program.exe` kaže da mu treba `CreateFileW` iz `kernel32.dll`
2) Wine-ov PE loader učita `kernel32.dll` i nađe pravu adresu funkcije `CreateFileW` i "kaže" to programu
3) Program zove `CreateFileW`, koji je deo Windows-ovog `Win32 API` (koji je veoma dobro dokumentovan), koji
   poziva `NtCreateFile`, koji je deo Windows-ovog internog `NT API` (koji je delimično dokumentovan) i koji
   predstavlja granicu sa Windows-ovim kernelom.
4) `NtCreateFile` je zapravo skup asemblerskih instrukcija koji na svom kraju skoči na `__wine_syscall_dispatcher`.
   Upravo ovde se desio skok sa PE (Windows) na ELF (Linux) format izvršnih fajlova.
5) Pomenuti dispečer je takođe napisan u asembleru i bavi se zamenom PE steka sa ELF stekom, i sa informacijama
   koje su mu prosleđene ume da nađe pravu `NtCreateFile` C funkciju, implementiranu u `ntdll.so`
   umesto u `ntdll.dll` i poziva je.
6) Funkcija `NtCreateFile` će odraditi potrebne konverzije, poput Windows putanja u Unix format putanje, i na kraju
   šalje zahtev za izvršenjem sistemskog poziva (u ovom slučaju `open()`) procesu pod imenom `wineserver` koji ima
   ulogu Windows kernela.

   Napomena: Neke `Nt` funkcije ne zovu `wineserver` već mogu i direktno da rade stvari poput `mmap`.

7) Konačno, `wineserver` izvrši `open` (tako što interaguje sa Linux jezgrom), a rezultat toga se onda propagira u
   suprotnom smeru do programa.

## Okruženje

Napomena: Kao referentni sistem je korišćena Linux distribucija `NixOS` i njen menadžer paketa `nix`.

U repozitorijumu će biti dat `shell.nix` fajl, koji predstavlja okruženje u koje se ulazi pomoću komande `nix-shell`
i koje će automatski dovući sve neophodne pakete za kompilaciju Wine-a iz njegovog izvornog koda, postaviti neke
promenljive okruženja koje će nam biti od koristi, kao i same alate poput `valgrind`, `clang-tools`, itd.

### Wine source

Pre nego što išta uradimo, s obzirom da će biti korišćen Valgrind, treba imati u vidu da
[Wine dokumentacija](https://gitlab.winehq.org/wine/wine/-/wikis/Wine-and-Valgrind) napominje da je neophodno imati
Valgrind već instaliran pre kompilacije Wine-a.
U dostupnom nix shell okruženju je valgrind dostupan samim ulaskom u njega, nakon čega se može započeti proces
kompilacije (zvanični priručnik: [link](https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine)).

> Napomena: Wine se tradicionalno kompajlovao više puta, u zavisnosti od arhitekture (32bit, 64bit, ...).
>
> Međutim, u verziji koju ovaj projekat analizira, postoji "`WoW64`" verzija, koja može da pokreće i 32bit
> i 64bit Windows aplikacije bez ikakvih 32bit Linux biblioteka, pa će to biti korišćeno radi lakše kompilacije.

Koraci za kompilaciju WoW64 verzije Wine-a (koristeći `nix`):

1) Kloniramo ovaj repozitorijum:

   ```bash
   git clone --recurse-submodules git@github.com:MATF-Software-Verification/2024_Analysis_wine.git
   cd 2024_Analysis_wine
   ```

2) Pokrenemo `setup.sh` koji će symlink-ovati `valgrind/wine-valgrind-scripts` na `wine/tools/valgrind`:

   ```bash
   bash setup.sh
   ```

3) Aktiviramo spremljeno `nix` okruženje:

   ```bash
   nix-shell
   ```

4) Premestimo se u `wine` direktorijum:

   ```bash
   cd wine
   ```

5) Pokrećemo `configure` skriptu:

   ```bash
   ./configure CC="ccache gcc" i386_CC="ccache i686-w64-mingw32-gcc" \
       x86_64_CC="ccache x86_64-w64-mingw32-gcc" \
       --enable-archs=i386,x86_64 CFLAGS="-g -Og -fno-inline"
   ```

> Napomena: CFLAGS preporuke uzete iz dokumentacije: [Compiler Optimizations & Call-Stacks](https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine#compiler-optimizations--call-stacks)


6) Pokrećemo `make`:

   ```bash
   make -j$(nproc)
   ```

7) Provera da je Wine prepoznao da je Valgrind instaliran:

``` bash
grep VALGRIND include/config.h
``` 
Ova komanda treba da vrati:
```bash
#define HAVE_VALGRIND_MEMCHECK_H 1
#define HAVE_VALGRIND_VALGRIND_H 1
```

## Spisak korišćenih alata

## Zaključak

## TODO

1) Komande za ne-nix sisteme
