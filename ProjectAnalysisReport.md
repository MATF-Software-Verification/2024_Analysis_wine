# Analiza projekta Wine

Ukoliko nije naznačeno eksplicitno, podrazumeva se WoW64 verzija Wine programa, kompajlovana na način opisan u README fajlu projekta.

## Valgrind 
Koristiće se podrazumevani Valgrindov alat, `memcheck`.

S obzirom na strukturu i prirodu programa Wine, zbog koje nije preterano zahvalan za analizu pomoću Valgrinda i sličnih alata, neophodno je odraditi pripremu pre pokretanja.
Priprema koja će biti opisana u nastavku je nastala na osnovu više izvora:
   1. [Wine and Valgrind](https://gitlab.winehq.org/wine/wine/-/wikis/Wine-and-Valgrind)
   2. [Compiler Optimizations & Call-Stacks](https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine#compiler-optimizations--call-stacks)
   3. [Autorovog forka projekta wine-valgrind-scripts](https://github.com/kubni/wine-valgrind-scripts) (originalni projekat: [link](https://github.com/austin987/wine-valgrind-scripts))
   
Prva dva izvora su iz zvanične dokumentacije i korišćena su najviše za neophodne i pomoćne flagove koji olakšavaju Valgrind-u da vrši analizu.
Treći izvor, wine-valgrind-scripts, je projekat čiji je original poslednji put ažuriran pre 8 godina i koji nam daje gotove skripte za pokretanje Wine testova (pojedinačnih ili celog skupa) i postavlja pomoćne promenljive okruženja kako bi analiza bila kvalitetnija.
Dodatno, uvodi i "suppression" fajlove  koji govore Valgrindu šta da preskače (npr. već poznate Wine bagove, itd.) kako bi se poboljšala čitljivost ispisa. 

Ova analiza je koristila fork tog projekta, sa malim izmenama kako bi radio na NixOS distribuciji (popravljen shebang u skriptama) i kako bi lepo radio sa AMD grafičkim kartama.

Dakle, priprema uključuje `source`-ovanje `vg-wrapper.sh` skripte, kao i postavljanje `WINETEST_WRAPPER` promenljive okruženja kako bi se testovi podrazumevano pokretali pod Valgrindom.

Dodatno, u jednom tabu terminala pokrećemo sledeće:
```bash
"$WINESRC/wine" start /min winemine
```
Ovo je bitno jer pokreće `wineserver`, ali bez Valgrinda.
Ovime preskačemo veliku količinu informacija koje bi nam Valgrind inače dao, a koje zapravo ne želimo, jer želimo samo testove da pokrenemo pod njim.

Naredni testovi će se izvršavati u drugom tabu terminala, bez gašenja prethodno pokrenutog wineserver-a. 

### Inicijalni rezultati testiranja

Prvi test koji je bio pokrenut pod Valgrindom je bio onaj spomenut u originalnom `wine-valgrind-scripts` repozitorijumu, `cred` iz modula `advapi32`, specifično 64bitna verzija:

```bash
rm -f x86_64-windows/cred.ok && \
    make x86_64-windows/cred.ok 2>&1 | \
    tee "$WINESRC/../valgrind/memcheck/advapi32-cred-x86_64.log"
```

Međutim, zanimljivo je da nikad nismo ni stigli do toga da se sam kod testa izvrši pod Valgrindom, i da je nakon određene faze inicijalizacije Wine-a test vratio poruku:

```text
make: *** [Makefile:21: x86_64-windows/cred.ok] Error 2
```

Ceo log je dostupan u repozitorijumu pod imenom `advapi32-cred-x86_64.log`, ali ćemo sad opisati najvažnije delove:

1. Prvi nalaz:

   ```text
   ==3525356== Syscall param ioctl(generic) points to uninitialised byte(s)
   ==3525356==    at 0x4984C3D: ioctl (in .../libc.so.6)
   ==3525356==    by 0x4ED4897: kernel_writewatch_init (virtual.c:291)
   ==3525356==    by 0x4EDBE48: virtual_init (virtual.c:3664)
   ==3525356==    by 0x4E9D4F9: __wine_main (loader.c:2297)
   ==3525356==    by 0x4801473: main (main.c:184)
   ==3525356==  Address 0x1ffefeada0 is on thread 1's stack
   ==3525356==  in frame #1, created by kernel_writewatch_init (virtual.c:283)
   ==3525356==  Uninitialised value was created by a stack allocation
   ==3525356==    at 0x4ED484C: kernel_writewatch_init (virtual.c:283)
   ```

   Kada pogledamo u `virtual.c:283`:

   ```c
   struct uffdio_api uffdio_api;
   // ...
   uffdio_api.api = UFFD_API;
   uffdio_api.features = UFFD_FEATURE_WP_ASYNC | UFFD_FEATURE_WP_UNPOPULATED;
   if (ioctl(/* ... */, &uffdio_api))
   // ...
   ```

   Ovde je problem što `uffdio_api` struktura zapravo ima tri polja, a treće se nikad ne inicijalizuje pre nego što se pošalje `ioctl`-u.

   Ono što je interesantno je što to deluje kao problem, ali zapravo je to sa Wine strane dobro odrađeno, jer je treći parametar i namenjen da bude prosleđen neinicijalizovan Linux jezgru, koje ga postavlja na neku vrednost (izvor: [man strana za uffdio_api](https://man7.org/linux/man-pages/man2/uffdio_api.2const.html)).

   To čini ovaj Valgrind-ov rezultat lažno-pozitivnim, i potencijalno bi mogao biti prijavljen Valgrind developerima.

2. Dolazimo do `error`-a zbog kojih je prekinut rad testa i Valgrinda:

   ```text
   0148:err:seh:segv_handler Got unexpected trap 0
   0148:err:virtual:virtual_setup_exception nested exception on signal stack addr 0x4eb1974 stack 0x7ffceb00
   ```

   Međutim, Valgrind nam ovde nije dao ništa detaljnije.

   Zbog toga, pokrenut je test opet, ali ovaj put bez `-q` opcije u `VALGRIND_OPTS` unutar `vg-wrapper.sh`. Test je zatim pokrenut na isti način, i napravljen novi log fajl pod nazivom `advapi32-cred-x86_64_no_q_flag.log`. U njemu je detaljnije opisan prethodni problem:

   ```text
   0148:err:seh:segv_handler Got unexpected trap 0
   vex amd64->IR: unhandled instruction bytes: 0x8E 0xD8 0x8E 0xC0 0x48 0x83 0xC4 0x8 0x5B 0x41
   vex amd64->IR:   REX=0 REX.W=0 REX.R=0 REX.X=0 REX.B=0
   vex amd64->IR:   VEX=0 VEX.L=0 VEX.nVVVV=0x0 ESC=NONE
   vex amd64->IR:   PFX.66=0 PFX.F2=0 PFX.F3=0
   ==3532226== valgrind: Unrecognised instruction at address 0x4eb1974.
   ==3532226==    at 0x4EB1974: leave_handler (signal_x86_64.c:955)
   ==3532226==    by 0x4EB3F82: setup_raise_exception (signal_x86_64.c:1637)
   ==3532226==    by 0x4EB44B5: segv_handler (signal_x86_64.c:2475)
   ==3532226==    by 0x48A719F: ??? (in .../libc.so.6)
   ==3532226==    by 0x6FFFFFBE0A2F: ??? (in .../dlls/ntdll/x86_64-windows/ntdll.dll)
   ==3532226== Your program just tried to execute an instruction that Valgrind
   ==3532226== did not recognise.  There are two possible reasons for this.
   ==3532226== 1. Your program has a bug and erroneously jumped to a non-code
   ==3532226==    location.  If you are running Memcheck and you just saw a
   ==3532226==    warning about a bad jump, it's probably your program's fault.
   ==3532226== 2. The instruction is legitimate but Valgrind doesn't handle it,
   ==3532226==    i.e. it's Valgrind's fault.  If you think this is the case or
   ==3532226==    you are not sure, please let us know and we'll try to fix it.
   ==3532226== Either way, Valgrind will now raise a SIGILL signal which will
   ==3532226== probably kill your program.
   0148:err:seh:segv_handler Got unexpected trap 0
   0148:err:virtual:virtual_setup_exception nested exception on signal stack addr 0x4eb1974 stack 0x7ffceb00
   ```

 Što se tiče `???` oznaka, za `libc` je zbog nedostatka debug simbola u verziji libc na `NixOS`,
dok je kod `ntdll.dll` iz zanimljivijeg razloga, a to je da Valgrind nema trenutno podršku za razrešavanje simbola za PE strane Wine-a prevedenu pomoću `mingw` (izvor: [Bug 211031](https://bugs.kde.org/show_bug.cgi?id=211031))

Dalje, kada pogledamo `leave_handler` u `signal_x86_64.c:955`, vidimo sledeću instrukciju:
   ```c
   __asm__ volatile( "movw %0,%%ds" :: "r" (ds64_sel) );
   ```

   Imajući u vidu da je `ds` segment registar kome procesor u 64bit modu postavi početnu adresu (bazu) na 0, i da se praktično ne koristi u 64bit režimu, kao i to da je sam Valgrind rekao da nije uspeo da parsira tu instrukciju, dolazimo do zaključka da najverovatnije i jeste bag, tj. neimplementirana situacija u Valgrindu. Isti test bi trebalo pokrenuti i u starijoj, ekskluzivno-64bit verziji Wine-a,, kao i u eksluznivno-32bit verziji Wine-a, kako bi se potvrdilo da nije problem samo u WoW64 verziji.

   Radi kompletnosti, pokrenuta je i 32bit verzija testa unutar WoW64 verzije, koja se nalazi u `advapi32/tests/i386-windows`, čiji je log u `advapi32-cred-i386.log`. Interesantno je što ovde isto test ne prolazi, ali zapravo nailazimo na drugačiji problem:

   ```text
   vex amd64->IR: unhandled instruction bytes: 0xCD 0x80 0x8B 0x4 0x24 0x67 0x8D 0x4 0xC5 0x3
   vex amd64->IR:   REX=0 REX.W=0 REX.R=0 REX.X=0 REX.B=0
   vex amd64->IR:   VEX=0 VEX.L=0 VEX.nVVVV=0x0 ESC=NONE
   vex amd64->IR:   PFX.66=0 PFX.F2=0 PFX.F3=0
   ==3532707== valgrind: Unrecognised instruction at address 0x4eae7ea.
   ==3532707==    at 0x4EAE7EA: alloc_fs_sel (in .../dlls/ntdll/ntdll.so)
   ```

   Problematična instrukcija je sada `int $0x80`, koja predstavlja 32bit-ni ekvivalent `syscall` instrukcije, koji je zvanično podržan na 64-bitnim arhitekturama, ali ga sam Valgrind ne podržava u tom scenariju, i ovo je već dokumentovani Valgrind bag ([Bug 342988](https://bugs.kde.org/show_bug.cgi?id=342988)).

   Dakle, da bismo videli da li naš originalni `ds` registar problem imamo i na 32bitnoj arhitekturi, neophodno bi bilo testirati "32bit-only" verziju Wine-a, s obzirom da Valgrind ne radi lepo u 32bit modu unutar WoW64 verzije Wine-a.

3. Još jedan jedini podatak koji nam je Valgrind dao pre nego što je ubijen proces:

   ```text
   ==3532226== 63 bytes in 1 blocks are definitely lost in loss record 13 of 28
   ==3532226==    at 0x484D7D0: malloc (in .../libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
   ==3532226==    by 0x4E99479: build_path (loader.c:264)
   ==3532226==    by 0x4E9B83A: init_paths (loader.c:459)
   ==3532226==    by 0x4E9D4AA: __wine_main (loader.c:2283)
   ==3532226==    by 0x4801473: main (main.c:184)
   ```

   Ako pogledamo `build_path`:

   ```c
   static char *build_path( const char *dir, const char *name )
   {
       size_t len = strlen( dir );
       char *ret = malloc( len + strlen( name ) + 2 );
       // ...

       return ret;
   }
   ```

   Ona je pozvana od strane `init_paths` (što se vidi i na steku poziva koji vraća Valgrind), koja nigde ne dealocira tu memoriju, pa imamo **definitivno curenje memorije** od 63 bajta.

   Razlog zbog kog ovo nije strašno je što se `init_paths` zapravo poziva jednom po `wine` procesu koji je pokrenut, i to unutar `__wine_main` funkcije, pa je to verovatno i razlog zašto do sad nije ništa urađeno povodom toga.



## Cppcheck
[Cppcheck](https://cppcheck.sourceforge.io/) je alat za statičku analizu koda koji se, prema njihovim rečima, veoma trudi da izbegne lažno-pozitivne prijave problema.

Kako bismo ga pokrenuli, neophodno je da generišemo `compile_commands.json`, fajl koji će mu pomoći da vidi sa kojim flag-ovima je fajl preveden,
od kojih su mu najbitnije dve: `-I` i `-D`. `-I` navodi direktorijume u kojima preprocesor treba da traži zaglavlja korišćena u fajlovima uz pomoć `#include` direktive.
`-D` definiše makro direktive preprocesora, identično kao `#define` u fajlu, a što Wine dosta koristi, na primer u vidu `#ifdef` direktiva.

Wine već ima u svom `Makefile` fajlu definisano sledeće:
```makefile 
depend: tools/makedep
	tools/makedep -C
```
Ako pogledamo u fajl `tools/makedep.c`:
```c
static const char Usage[] =
    "Usage: makedep [options]\n"
    "Options:\n"
    "   -C          Generate compile_commands.json along with the makefile\n"
    "   -S          Generate Automake-style silent rules\n"
    "   -fxxx       Store output in file 'xxx' (default: Makefile)\n";
```
Vidimo da Wine već ima implementiran način za automatsko generisanje `compile_commands.json`, tako da to i mi koristimo.

Sada treba to proslediti cppcheck-u.
Međutim, s obzirom da Wine-ov `compile_commands.json` ima oko 65 hiljada linija, nećemo pokretati `cppcheck` nad celim repozitorijumom,
već ćemo ga ograničiti na "Unix stranu" (ELF stranu) Wine-a.
Inicijalni test `cppcheck`-a je onda prosto:
```bash
cppcheck --project=compile_commands.json --file-filter='dlls/ntdll/unix/*'
```
Međutim, postoje 2 problema sa ispisom ove komande:
   1. `cppcheck` podrazumevano ispisuje samo `error` nalaze
   2. Dobijamo sledeći `error` skoro odmah na početku ispisa:
   ```text
   include/winnt.h:2021:2: error: #error You need to define a CONTEXT for your CPU [preprocessorErrorDirective]
   ```
Oba problema ćemo rešiti odgovarajućim flag-ovima:
   1. `--enable=warning,style,performance,portability`
   2. [ ] ` -D__x86_64__ -Dlinux`
Prvi sam sebe opisuje, dok je drugi zanimljiviji.
Naime, ako pogledamo mesto gde se desila greška koja je smetala cppcheck-u:
```c
#if !defined(CONTEXT_FULL) && !defined(RC_INVOKED)
#error You need to define a CONTEXT for your CPU
#endif
```
Vidimo da nemamo definisane ove makro direktive.
Kratkom pretragom u fajlu nalazimo šta je neophodno da bi ih Wine definisao:
```c
#ifdef __x86_64__
// ...
#define CONTEXT_FULL CONTEXT_AMD64_FULL
// ...
```
`-Dlinux` je dodat zbog druge `#ifdef` promene, konkretno iz `dlls/ntdll/unix/signal_x86_64.c` koji nam je poznat još iz Valgrind sekcije:
```c
#ifdef linux
// ...
#elif defined(__FreeBSD__) || defined (__FreeBSD_kernel__)
// ...
#elif defined(__NetBSD__)
// ... 
#elif defined (__APPLE__)
// ...
#else
#error You must define the signal context functions for your platform
```

Biće dodato i još par manje zanimljivih flag-ova:
```bash
    --platform=unix64 \
    -j"$(nproc)" \
    --xml --xml-version=2 2> cppcheck/cppcheck-ntdll-unix.xml
```
`--platform` će reći cppcheck-u veličine tipova na našoj platformi (x86_64 Linux),
dok se će xml izveštaj biti iskorišćen za generisanje html izveštaja pomoću `cppcheck-htmlreport`. Podrazumevano `cppcheck` ispisuje na `stderr`, što generator izveštaja ne ume da čita.
Dakle, cela komanda koju ćemo pokrenuti je sledeća:
```bash
cd "$WINESRC" && cppcheck \
    --project=compile_commands.json \
    --file-filter='dlls/ntdll/unix/*' \
    --enable=warning,style,performance,portability \
    -D__x86_64__ -Dlinux \
    --platform=unix64 \
    -j"$(nproc)" \
    --xml --xml-version=2 \
    2> ../cppcheck/cppcheck-ntdll-unix.xml
```
Ovaj put nema one greške od malopre, pa generišemo html izveštaj radi bolje preglednosti,
kako ne bi morali da čitamo xml direktno:
```bash
cd "$WINESRC" && cppcheck-htmlreport \
    --file=../cppcheck/cppcheck-ntdll-unix.xml \
    --report-dir=../cppcheck/html \
    --source-dir=.
```
Ovo će izgenerisati html fajl u `cppcheck/html/index.html` koji možemo pogledati u internet pretraživaču.
`cppcheck` je napravio `462` prijave ukupno: `338` stilskih, `77` upozorenja, `36` grešaka i `11` prijava vezanih za portabilnost.
Ovaj izveštaj će se većinski fokusirati na greške.
Jedna od veoma zanimljivih grešaka je sledeća ():
```c
static void add_option( const char *name, unsigned char set, unsigned char clear )
{
    // ....
    if (nb_debug_options >= options_size)
    {
        options_size = max( options_size * 2, 16 );
        debug_options = realloc( debug_options, options_size * sizeof(debug_options[0]) );<--- Common realloc mistake: 'debug_options' nulled but not freed upon failure
    }

    pos = min;
    if (pos < nb_debug_options) memmove( &debug_options[pos + 1], &debug_options[pos],
                                         (nb_debug_options - pos) * sizeof(debug_options[0]) );
    strcpy( debug_options[pos].name, name );
    debug_options[pos].flags = (default_flags & ~clear) | set;
    nb_debug_options++;
}
```
Sam `cppcheck` nam sugeriše šta se desilo.
Suština problema je da `realloc` može da ne uspe, na primer kada nema dovoljno slobodne memorije da se realociranje desi.
U tom slučaju, `realloc` će vratiti NULL.
Ovde će to napraviti 2 problema:
   1. Curenje memorije: stara memorija na koju je `debug_options` pokazivao neće nikako moći da bude dealocirana, ikad više, jer više nema pokazivača na nju, a `realloc` ne dealocira to automatski.
   2. SEGFAULT: Nema provere da li je `debug_options == NULL`, a neposredno nakon `realloc` se `debug_options` koristi na više mesta, tako da je greška neizbežna. 

Oko ovog problema je kontaktiran i jedan od Wine developera putem IRC-a, koji je potvrdio da ovo može da se desi, ali i dao sledeće obrazloženje:
> "Considering the function is called only during early process boot (when the process executes its first trace() call ever, way before entering the exe's main), and the allocation can't go above a kilobyte unless user passes an insane WINEDEBUG env, it failing means zero chance the process would subsequently boot correctly, so I'd say not worth fixing."

Praktično, pod normalnim okolnostima, `realloc` bi pao zbog nedostatka memorije samo ako na sistemu nema ni `1KB` dodatnog slobodnog prostora. Ako zanemarimo sve druge probleme koje bi ovakav sistem imao, u ovom slučaju je bitno i to kada se ova funkcija izvršava. S obzirom da se izvršava i pre nego što je zapravo pokrenut Windows `.exe` program, ovo ne može da se desi u sred korišćenja programa. Čak i kad bismo popravili bag da Wine preživi neuspešan `realloc` ovde, svakako bi došlo do greške, samo par koraka kasnije, jer Wine mora da alocira svoje potrebne strukture, a što neće moći da uradi usled toga što sistem nema ni 1KB slobodne memorije.
Što se tiče konkretne vrednosti od 1KB prostora koja je spomenuta, ona odgovara tačno 64 debug kanala, s obzirom da jedan kanal ima 16 bajtova:
```c
// debug.h
struct __wine_debug_channel
{
    unsigned char flags;
    char name[15];
};
```
Napomena: Sam kod zapravo ne ograničava taj broj nikako, pa bi u teoriji korisnik mogao da prosledi WINEDEBUG koja zahteva i više od jednog kilobajta, ali problem i dalje ostaje isti.



## Clang-tidy
[clang-tidy](https://clang.llvm.org/extra/clang-tidy/) je statički analizator koji je deo `clang` / `llvm` ekosistema, i sastoji se iz dva bitna dela:

Prvi su provere nad apstraktnim sintaksnim stablom (`bugprone-*`, `readability-*`, `performance-*`), koje traže sumnjive obrasce u kodu.

Drugi je **Clang Static Analyzer** (`clang-analyzer-*`), koji radi simboličko izvršavanje: prolazi kroz program putanju po putanju, na svakom grananju bira granu, pamti ograničenja koja iz tog izbora slede, i tako donosi zaključke o vrednostima promenljivih na svakoj konkretnoj putanji.

Analiza će se skoro isključivo fokusirati na samo određene `bugprone` prijave, kao i na Clang Static Analyzer koji je deo Clang-tidy alata,
dok će stilske prijave biti isključene u velikoj meri.
Specifično, komanda će iskoristiti flag `-*` da izbaci sve podrazumevane vrste prijava, a zatim će vratiti one koje mogu biti zanimljive: `clang-analyzer-*`, vratiti celu `bugprone`
klasu, a onda opet skinuti sve koje nam nisu zanimljive:

```bash
cd "$WINESRC" && run-clang-tidy -p . -j"$(nproc)"     -checks='-*,bugprone-*,clang-analyzer-*,-bugprone-easily-swappable-parameters,-bugprone-narrowing-conversions,-bugprone-assignment-in-if-condition,-bugprone-suspicious-string-compare,-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling,-clang-analyzer-security.insecureAPI.strcpy' 'dlls/ntdll/unix/.*\.c' > "$WINESRC/../clang-tidy/clang-tidy-ntdll-unix.txt" 2>&1
```

Kao što vidimo, opet analiziramo samo `unix` fajlove iz `ntdll`, dakle isto kao pre.
Umesto gledanja celog generisanog log fajla, možemo iskoristiti `grep` da pogledamo samo prijave od strane Clang Static Analyzer-a, i to recimo za proveru pristupa nizu:
```bash
grep -n "clang-analyzer-security.ArrayBound" "$WINESRC/../clang-tidy/clang-tidy-ntdll-unix.txt"
```
Neki od rezultata nam govore da postoji potencijalna "out of bounds" greška, međutim za neke clang-tidy deluje ubeđeno. Evo primera jednog takvog rezultata:
```text
1561:dlls/ntdll/unix/security.c:378:42: warning: Out of bound access to memory after the end of 'info_len' [clang-analyzer-security.ArrayBound]
```
Sad možemo da pogledamo i malo detaljnije šta je govorio u logu o tome:
```c
dlls/ntdll/unix/security.c:378:42: warning: Out of bound access to memory after the end of 'info_len' [clang-analyzer-security.ArrayBound]
  378 |     if (class < MaxTokenInfoClass) len = info_len[class];
      |                                          ^~~~~~~~~~~~~~~
dlls/ntdll/unix/security.c:376:5: note: Assuming the condition is true
```
Ovde možemo videti da Clang Static Analyzer zapravo razlikuje i beleži izbore prilikom `if` grananja, što Cppcheck recimo nije radio.
Vidimo da ovde tvrdi da se u THEN grani dešava problem.
Da bismo proverili da li je u pitanju lažno-pozitivni nalaz, pogledajmo malo detaljnije originalan Wine `security.c` fajl:
```c
/***********************************************************************
 *             NtQueryInformationToken  (NTDLL.@)
 */
NTSTATUS WINAPI NtQueryInformationToken( HANDLE token, TOKEN_INFORMATION_CLASS class,
                                         void *info, ULONG length, ULONG *retlen )
{
    static const ULONG info_len [] =
    {
        0,
        0,    /* TokenUser */
        0,    /* TokenGroups */
        0,    /* TokenPrivileges */
        0,    /* TokenOwner */
        0,    /* TokenPrimaryGroup */
        0,    /* TokenDefaultDacl */
        sizeof(TOKEN_SOURCE), /* TokenSource */
        sizeof(TOKEN_TYPE),  /* TokenType */
        sizeof(SECURITY_IMPERSONATION_LEVEL), /* TokenImpersonationLevel */
        sizeof(TOKEN_STATISTICS), /* TokenStatistics */
        0,    /* TokenRestrictedSids */
        sizeof(DWORD), /* TokenSessionId */
        0,    /* TokenGroupsAndPrivileges */
        0,    /* TokenSessionReference */
        0,    /* TokenSandBoxInert */
        0,    /* TokenAuditPolicy */
        0,    /* TokenOrigin */
        sizeof(TOKEN_ELEVATION_TYPE), /* TokenElevationType */
        sizeof(TOKEN_LINKED_TOKEN), /* TokenLinkedToken */
        sizeof(TOKEN_ELEVATION), /* TokenElevation */
        0,    /* TokenHasRestrictions */
        0,    /* TokenAccessInformation */
        0,    /* TokenVirtualizationAllowed */
        sizeof(DWORD), /* TokenVirtualizationEnabled */
        sizeof(TOKEN_MANDATORY_LABEL) + sizeof(SID), /* TokenIntegrityLevel [sizeof(SID) includes one SubAuthority] */
        sizeof(DWORD), /* TokenUIAccess */
        0,    /* TokenMandatoryPolicy */
        0,    /* TokenLogonSid */
        sizeof(DWORD), /* TokenIsAppContainer */
        0,    /* TokenCapabilities */
        sizeof(TOKEN_APPCONTAINER_INFORMATION) + sizeof(SID), /* TokenAppContainerSid */
        0,    /* TokenAppContainerNumber */
        0,    /* TokenUserClaimAttributes*/
        0,    /* TokenDeviceClaimAttributes */
        0,    /* TokenRestrictedUserClaimAttributes */
        0,    /* TokenRestrictedDeviceClaimAttributes */
        0,    /* TokenDeviceGroups */
        0,    /* TokenRestrictedDeviceGroups */
        0,    /* TokenSecurityAttributes */
        0,    /* TokenIsRestricted */
        0     /* TokenProcessTrustLevel */
    };


    // ....

    if (class < MaxTokenInfoClass) len = info_len[class];
```
Ovde vidimo da `info_len` ima 42 definisana elementa.
Proverimo sad `TOKEN_INFORMATION_CLASS`, koji predstavlja enum tip od `class`:
```c
// wine/include/winnt.h
typedef enum _TOKEN_INFORMATION_CLASS {
    TokenUser = 1,
    TokenGroups = 2,
    TokenPrivileges = 3,
    // ... Skraceno zbog preglednosti, ide redom
    TokenIsAppSilo = 48,
    TokenLoggingInformation = 49,
    TokenLearningMode = 50,
    MaxTokenInfoClass
} TOKEN_INFORMATION_CLASS;
```
Vidimo da ovde ima 51 element!
Vratimo se `if` naredbu:
```c
if (class < MaxTokenInfoClass) len = info_len[class];
```
Vidimo da nas trenutni uslov štiti ukoliko bi neko prosledio vrednost veću od `MaxTokenInfoClass`, i to bi bilo dovoljno.... kad bi dužina `info_len` niza bila identična broju elemenata `TOKEN_INFORMATION_CLASS` enuma.
Međutim, verovatno je neko u nekom trenutku dodao tih 9 enum elemenata, a zaboravio da proširi `info_len` niz, pa u slučaju da je `class` u `[41, ..., 51]`, imamo zaista **pristup nizu van opsega**!

Autor smatra da treba uraditi dve stvari u ovom slučaju:
   1. Dopuniti `info_len` niz sa dodatnih 9 elemenata, pri čemu treba biti oprezan i proveriti
      koje vrednosti zapravo treba da budu na tim mestima, da li obične nule ili neki `sizeof`.
      
   2. Promeniti `if` uslov u `if(class < ARRAY_SIZE(info_len))` čime će biti sprečeno ovako nešto zauvek. I dalje je prvi deo neophodan, ukoliko želimo tu funkcionalnost.
   
> Napomena: Na Wine commit-u koji projekat analizira, ispod ovog koda postoji `switch(class)` koji ne obrađuje tih 9 "skorije dodatih" elemenata, pa bi i samo promena 2 funkcionisala, ali autor smatra da je radi kompletnosti bolje odraditi i promenu 1.

Ovo će biti prijavljeno Wine timu.


## UndefinedBehaviorSanitizer (UBSan)
[UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html) je detektor nedefinisanog ponašanja. Za razliku od `cppcheck` i `clang-tidy` koji su vršili statičku analizu, UBSan vrši dinamičku analizu.

UBSan zahteva od nas da prevedemo kod sa instrumentacijom.
Zbog toga je neophodna izmena Wine build sistema, koja je data u `custom.patch` fajlu,
i dodaje `-fsanitize=undefined` i `-fno-omit-frame-pointer` u `UNIX_CFLAGS` i `-fsanitize=undefined` u `UNIX_LIBS`. Prvo je neophodno da bi se instrumentacija uključila,
a drugo da bi kompajler umeo da razreši `__ubsan_handle_*` simbole.

Sama UBSan dokumentacija predlaže `'fsanitize=undefined` kao flag koji dodaje određenu količinu provera koje predstavljaju nešto osnovno što UBSan radi, dok je `-fno-omit-frame-pointer` dodat zbog `print_stacktrace=1` da bi mogao stek da se rekonstruiše.

### Koraci
   1. Primenimo izmenu:
    ```bash
   cd $WINESRC && git apply ../custom.patch
   ```
   2. Zbog izmene u `Makefile.in`, neophodno je regenerisati `compile_commands.json` i ponovo kompajlovati Wine:
   ```bash
   make depend
   make clean
   make -j$(nproc)
   ```
   3. Za svaki slučaj ažuriramo prefiks (ili napravimo ukoliko ga nemamo):
```bash
      ./wine wineboot -u
```
   4. Pokrenemo isti test kao kod Valgrinda, `cred` iz `advapi32` modula.
```bash
   export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0:log_path=../ubsan/ubsan"
   cd dlls/advapi32/tests && rm -f x86_64-windows/cred.ok && make x86_64-windows/cred.ok
```
>  `halt_on_error=0` znači da se izvršavanje nastavlja posle prijave, pa se u jednom prolazu prikupe sve. `log_path` pravi po jedan fajl po procesu (`ubsan.PID`), jer jedno pokretanje testa podigne više Wine procesa, a svi koriste isti instrumentisani `ntdll.so`.
   5. Grepujemo npr. samo `runtime error` greške:
```bash
   cat "$WINESRC/../ubsan/"ubsan.* 2>/dev/null | grep "runtime error"
```

Hajde da razmotrimo poznati `debug.c` fajl, ali ovaj put sa drugačijom greškom:
```text
dlls/ntdll/unix/debug.c:366:5: runtime error: null pointer passed as argument 2, which is declared to never be null
```
Pogledajmo kod:
```c
void dbg_init(void)
{
    struct __wine_debug_channel *options, default_option = { default_flags };

    setbuf( stdout, NULL );
    setbuf( stderr, NULL );

    if (nb_debug_options == -1) init_options();

    options = (struct __wine_debug_channel *)((char *)peb + (is_win64 ? 2 : 1) * page_size);
    memcpy( options, debug_options, nb_debug_options * sizeof(*options) ); // Problematična linija
    free( debug_options );
    debug_options = options;
    options[nb_debug_options] = default_option;
    init_done = TRUE;
}
```
UBSan tvrdi da je u problematičnom pozivu `memcpy` funkcije drugi argument, tj. `debug_options` zasigurno NULL u našem pokretanju bio.
Ukratko:
   1. Funkcija `init_options` čita `WINEDEBUG` promenljivu okruženja i smešta to u svoju `wine_debug` promenljivu. 
   2. Funkcija `parse_options` parsira opcije i dodaje ih sa `add_options`
   3. Promenljiva`debug_options` se realocira i koristi kao globalna promenljiva u funkciji `dbg_init` koju vidimo iznad.
   
Ovde vidimo prednost dinamičke analize, i ovo je nešto što `cppcheck` i `clang-tidy` nisu uspeli da uhvate, a to je da je `debug_options` zaista u našem pokretanju bio `NULL` jer nismo definisali `WINEDEBUG`.

Prosleđivanje `debug_options` koji je `NULL` neće imati velike posledice jer je treći argument veličina koja će biti 0, ali je to i dalje **formalno nedefinisano ponašanje**, jer [standard](https://port70.net/~nsz/c/c11/n1570.html#7.1.4) traži da pokazivači budu validni i kada je broj bajtova nula.
> Isečak iz standarda: If an argument to a function has an invalid value (such as a value outside the domain of the function, or a pointer outside the address space of the program, or a **null pointer**, or a pointer to non-modifiable storage when the corresponding parameter is not const-qualified) or a type (after promotion) not expected by a function with variable number of arguments, the behavior is undefined.













































