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

### Ne-nix sistemi
Preporučen način je instalirati [nix](https://nixos.org/download/) menadžer paketa, koji radi na svim 
poznatijim distribucijama.

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
   # git clone --recurse-submodules git@github.com:MATF-Software-Verification/2024_Analysis_wine.git # SSH varijanta
   git clone --recurse-submodules https://github.com/MATF-Software-Verification/2024_Analysis_wine.git
   cd 2024_Analysis_wine
   ```

2) Pokrenemo `setup.sh` koji će symlink-ovati `valgrind/wine-valgrind-scripts` na `wine/tools/valgrind`:

   ```bash
   bash setup.sh
   ```

3) Sredimo promenljive okruženja u `shell.nix`:
   * `WINESRC` koja pokazuje na `wine` repozitorijum
   * `WINEPREFIX` koji će reći Wine-u gde da napravi prefiks, direktorijum u kom će Wine da imitira Windows hijerarhiju direktorijuma
   * `CCACHE_BASEDIR` koji treba da bude jedan direktorijum iznad kloniranog repozitorijuma
   
4) Aktiviramo spremljeno `nix` okruženje:

   ```bash
   nix-shell
   ```

5) Premestimo se u `wine` direktorijum:

   ```bash
   cd wine
   ```

6) Pokrećemo `configure` skriptu:

   ```bash
   ./configure CC="ccache gcc" i386_CC="ccache i686-w64-mingw32-gcc" \
       x86_64_CC="ccache x86_64-w64-mingw32-gcc" \
       --enable-archs=i386,x86_64 CFLAGS="-g -Og -fno-inline"
   ```
> Napomena: CFLAGS preporuke uzete iz dokumentacije: [Compiler Optimizations & Call-Stacks](https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine#compiler-optimizations--call-stacks)

7) Pokrećemo `make`:

   ```bash
   make -j$(nproc)
   ```

8) Provera da je Wine prepoznao da je Valgrind instaliran:

``` bash
grep VALGRIND include/config.h
``` 
Ova komanda treba da vrati:
```bash
#define HAVE_VALGRIND_MEMCHECK_H 1
#define HAVE_VALGRIND_VALGRIND_H 1
```

## Spisak korišćenih alata
  * [Valgrind Memcheck](https://valgrind.org/docs/manual/mc-manual.html) 
  * [Cppcheck](https://cppcheck.sourceforge.io/)
  * [clang-tidy](https://clang.llvm.org/extra/clang-tidy/)
  * [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
  * winetest + [gcov](https://gcc.gnu.org/onlinedocs/gcc/Gcov.html)
  * [perf](https://perfwiki.github.io/main/)

## Zaključak
Motivacija za odabir Wine kao projekta za analizu je bila jednostavna: projekat je star 33 godine i pisan je u programskom jeziku C, što je autoru delovalo kao pogodan izbor za testiranje alata,
usled raznih malih i velikih problema koje je lako prevideti u C kodu, pogotovo kada postoji više miliona linija koda.

Analiziran je 21 fajl Unix strane `ntdll` modula (`wine/dlls/ntdll/unix`) uz pomoć 6 alata iz različitih kategorija:
 * statička analiza (`cppcheck`, `clang-tidy`)
 * dinamička analiza (`Valgrind Memcheck`, `UBSan`)
 * testiranje sa merenjem pokrivenosti (`winetest` + `gcov`)
 * profilisanje (`perf`)
 
### Pronađeni problemi
#### Wine
##### Greške
Što se tiče Wine, glavni problem pronađen u `ntdll/unix/security.c`, gde je `clang-tidy` Clang Static Analyzer ukazao na **pristupanje nizu van okvira** koje se dešava pod 
specifičnim okolnostima koje su opisane detaljno u izveštaju. Vezano za taj bag je kreiran i [autorov merge request](https://gitlab.winehq.org/wine/wine/-/merge_requests/11958) na zvaničnom 
Wine Gitlab repozitorijumu, a čiji se epilog i dalje čeka, u trenutku pisanja ovog zaključka.

Uz pomoć `cppcheck` alata je pronađeno neželjeno ponašanje u `ntdll/unix/debug.c` u vezi sa pozivom `realloc` funkcije, a koje nastaje kada `realloc` ne uspe da se izvrši usled nedostatka memorije,
što kasnije uzrokuje `SIGSEGV`. Za ovaj problem nije napravljena ispravka, nakon konsultacije sa jednim od aktivnijih Wine programera, jer se dešava dovoljno rano, a uslov da se desi je takođe toliko 
katastrofalan (~1KB-1MB slobodnog prostora na mašini) da bi Wine svakako prestao sa radom, čak i ako se problem ispravi.

Pronađeno je i malo curenje od 63 bajta, na samom početku Wine procesa, koje se isto dešava samo jednom po pokretanju procesa, i isto je zanemarljivo.

##### Uska grla
Profilisanje kratkotrajnih procesa (profilisan je `file` test) pokazuje da 37% vremena odlazi na baratanje fontovima (`libfreetype`, `libfontconfig`, ...), 
a još 6.09% na `find_env_var`, funkciju koja linearno pretražuje Windows okruženje pri svakom postavljanju promenljive.

Uzrok skeniranja fontova je Wine implementaciona odluka i u merenju se ponavlja u svakom procesu, dok je vreme provedeno u `find_env_var` posledica interesantnog dizajna Windows okruženja.
Zbog prirode ovih funkcija, možemo da zaključimo da ove stvari uzimaju veliki deo vremena kratkotrajnim procesima, dok kod dugotrajnih programa nisu preterano bitne, s obzirom da se njihova cena plati
jednom i to je to.

#### Valgrind
Valgrind dobija svoj poseban deo, s obzirom na količinu ~~muke~~ posla koju je zadao autoru projekta.
Autor je koristio `WoW64` verziju Wine-a, koji je prva preporuka u zvaničnoj Wine dokumentaciji, i koji može da pokrene 32-bitne aplikacije u 64-bitnom okruženju, bez ikakvih 32-bitnih biblioteka.
Valgrindu, koji je kroz istoriju često imao čudne interakcije sa Wine-om, ovo nije preterano odgovaralo,
pa je autor naišao na bagove u Valgrindu, tražeći bagove u Wine-u. 
Oba potvrđena baga, kao i 1 potencijalni,  su opisani u izveštaju detaljno, ali ukratko:
   * Jedan od bagova je bio vezan za `ioctl` funkciju, kojoj se prosleđuju struktura sa 3 polja kojoj je neophodno popuniti samo 2 polja, s obzirom da Linux jezgro popunjava treće.
     Međutim, Valgrind nije svestan toga.
     Autor je u vezi ovoga bio u kontaktu sa istim malopre pomenutim Wine programerom, koji je uz dogovor sa autorom o tome obavestio Valgrind programere: [Bug 525637](https://bugs.kde.org/show_bug.cgi?id=525637)
   * Drugi bag je vezan za korišćenje `int 0x80` instrukcije koja služi za sistemske pozive u 32-bitnom okruženju. Problem je što može da se koristi i u 64-bitnom, ali Valgrind to ne podržava.
     Autor ovo nije prijavio pošto već postoje 2 odvojene prijave: [Bug 342988](https://bugs.kde.org/show_bug.cgi?id=342988) i [Bug 454482](https://bugs.kde.org/show_bug.cgi?id=454482)
     
   * Treći bag, i jedini koji nije skroz potvrđen, ali po autorovom mišljenju isto jeste problem, je upis u segmentni registar `ds`. 
     Koliko je autor uspeo da istraži, ovo je zvanično podržano u 64-bitnom okruženju, ali ga praktično niko ne koristi tu, pa ga najverovatnije ni Valgrind ne implementira.
     

### Završna reč
Glavni rezultati analize su 2 pronađena baga u Wine-u, od kojih je jedan ozbiljan i ispravka je poslata iskusnijim Wine programerima na proveru, kao i 1 (potencijalno 2) nova i 1 stari bag u Valgrind-u (konkretno u njegovoj VEX međureprezentaciji).
Pored toga, autor je stekao uvid u rad Wine programa, kao i potpuno novo iskustvo rada na projektu ovog obima, uz korišćenje alata za analizu.

## TODO
1) Komande za ne-nix sisteme
