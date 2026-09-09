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
