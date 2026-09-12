# PanoWizard – arbetsinstruktioner för Codex

## Produkt och principer

- PanoWizard är en native SwiftUI-app för macOS med en enda inbyggd
  C++17/OpenCV-motor.
- Arbeta enligt KISS: gör den minsta tydliga ändringen som löser den uttryckliga
  uppgiften. Lägg inte till parallella motorvägar, dolda feature flags eller
  panorama-specifika specialfall.
- Utdata från motorn ska vara ett komplett equirektangulärt 360° × 180°-
  panorama i proportionen 2:1.
- Taggen `best-ever` är den manuellt verifierade visuella referensen för
  panoramana A–S. Ändra inte verifierat bildbeteende utan ett tydligt skäl och
  en uttryckligt avgränsad valideringsplan.
- AI-retusch och Little Planet är eftersteg som läser det färdiga panoramat.
  De får aldrig kopplas in i geometri, ownership, sömval eller blending.

## Arkitektur

- `Sources/PanoWizard/Models/PanoProject.swift` definierar projektformat v7;
  avkodaren accepterar även v6.
- `Sources/PanoWizard/Services/OpenCVPanoramaEngine.swift` förbereder
  orienterade TIFF-källor och masker, väljer cachefil och vidarebefordrar
  progress och avbrytning genom C-API:t.
- `Sources/PanoWizard/Services/SourceImageRaster.swift` applicerar ImageIO:s
  metadataorientering och därefter användarens manuella kvartsvarv på samma
  sätt för miniatyr, källförhandsvisning och motorkälla.
- `Sources/PanoWizard/Services/MaskedSourceImageWriter.swift` lägger den röda
  exkluderingsmasken i källans alpha. Maskerade pixlar får inte användas senare
  i motorn.
- `Sources/OpenCVBridge/PanoramaBridge.cpp` innehåller hela panoramaalgoritmen.
  Håll den oberoende av SwiftUI, dokumentlagring och testprojektnamn.
- Gröna skyddsmasker skickas separat till motorn och påverkar sömprioritet;
  de skapar aldrig nytt bildinnehåll.
- `Sources/PanoWizard/ViewModels/AppModel.swift` binder dokument, motor,
  förhandsvisning, retusch och export till UI-livscykeln.

## Känslig panoramakedja

Läs alltid implementationen före en motorändring. Nuvarande ordning är:

1. optisk bildcirkel och giltig källtäckning
2. SIFT och ömsesidig feature-matchning
3. rotations-RANSAC och robust gemensam kamera-/linsoptimering
4. horisontutjämning och separat registrering av reparationsbilder
5. sfärisk warp med alpha, centralitet och skyddsmasker
6. global radiometrisk kompensation
7. redundansfilter och central täckningsprioritet
8. GraphCut-labels/ownership och konfliktmask
9. validerad sömlokal lågfrekevent radiometri på respektive källager
10. innehållsanpassad blending
11. slutlig orientering och JPEG-export

Steg 9 blandar inte RGB mellan ägare. Det estimerar ett mycket lågfrekevent
fält från giltiga, oklippta och låggradienta överlappspixlar, validerar det mot
separata pixlar och applicerar symmetrisk korrigering på källagren före
compositing.

Steg 10 bevarar GraphCut-detalj med en smal feather, använder bredare
lågfrekevent tonutjämning där källorna är konsekventa och skyddar struktur och
konflikt. I högkonfliktgrenen finns en minimum-feather som motsvarar sigma
12 px vid 4096 px panoramabredd, skalas med upplösningen och aktiveras av
befintlig struktur-, konflikt-, sömkonsekvens- och radiometrisk
steginformation. Ändra inte dess uttryck, trösklar, radier, vikter eller
upplösningsskalning som en del av annan cleanup.

Sfärisk RGB-projektion är validitetsnormaliserad: färg och giltighetsvikt
projiceras med samma Lanczos-kärna och färgen divideras bara där vikten är
tillräcklig. Efter uppskalning skärs varje GraphCut-ägarmask alltid med samma
bilds fullupplösta `warp.mask`; befintlig fallback fyller eventuellt frilagda
pixlar från en annan giltig bild.

När en GraphCut-överlappning korsar panoramats periodiska 0°/360°-gräns packas
bildparets relevanta ytor till en kompakt sammanhängande ROI, körs genom samma
GraphCut och mappas tillbaka periodiskt. Övriga överlappningar använder den
ursprungliga kodvägen.

Projicerade användarexkluderingar hålls separat från den allmänna
validitetsmasken. Slutblandningen går tillbaka till den smala
GraphCut-kompositen i och kring exkluderingen så att bortmaskerat innehåll inte
återinförs. En lågfrekevent tonö kan fortfarande synas när fallbackbildens ton
skiljer sig från omgivningen; det finns ingen separat tonkorrigering för detta.

Feature matching, CP, linsmodell, geometri, warp, GraphCut, ownership,
masklogik, radiometri och blendval är kopplade. Anta inte att en synlig söm
motiverar en generell featherbredd eller ändrat ownership. Mät först det
relevanta mellansteget och håll diagnostik skild från produktionskod.

## Kodkonventioner

- Använd domännamn som beskriver permanent funktion; märk inte aktiv kod som
  prototyp eller experiment.
- Kommentarer ska förklara varför icke-trivial logik eller en invariant finns,
  inte återberätta utvecklingshistoriken.
- Ändra inte numeriska algoritmparametrar i en rename, cleanup eller annan
  orelaterad uppgift.
- Produktionsmotorn får bara läsa uttryckligt valda originalbilder och deras
  masker. Autodetektera aldrig andra bilder som råkar ligga i samma katalog.
- Lägg inte in filnamn, testcase-ID:n eller lokala sökvägar i produktionsbeslut.
- Bevara dokumentkompatibilitet. Källor, masker, panorama, förhandsvisningsvy
  och retuschdata ska överleva stödda migreringar.
- Uppdatera `README.md` och denna fil när arkitektur eller arbetsregler faktiskt
  ändras; skapa inte nya historikdokument för tillfälliga undersökningar.

## Verifiering

Välj verifiering proportionellt mot ändringen:

1. Kör alltid `swift build` efter kod- eller buildändringar.
2. Kör endast berörda fokuserade testsviter när uppgiften tillåter tester.
3. Kör `./Scripts/build-app.sh` när appaket, resurser, native länkning eller
   filnamn i byggträdet har ändrats.
4. Kör inte hela A–S-regressionen slentrianmässigt. Beskriv syfte, valda fall
   och förväntade risker och invänta uttrycklig omfattning när användaren vill
   granska visuellt själv.
5. Använd bara originalkällor i bildregressioner och håll gamla renderade
   resultat utanför automatisk källupptäckt.

Efter en refaktorering ska diffen granskas för ändrade konstanter,
algoritmuttryck, ordning, maskvillkor och cachebeteende. En lyckad kompilering
är inte bevis för oförändrat visuellt resultat.

## Git och checkpoints

- Kontrollera `git status` före arbete. Bevara användarens orelaterade
  ändringar och fråga om mål överlappar.
- Skapa en namngiven restore point före riskfyllda motorförändringar när
  användaren ber om det. Flytta eller skriv aldrig om en verifierad tagg.
- Commit/pusha endast på uttrycklig begäran. Blanda inte experiment,
  diagnostikartefakter eller genererade panoraman med produktionsändringar.
- Vid återställning: verifiera commit/tagg, working tree, build och remote enligt
  användarens exakta instruktioner innan ytterligare arbete.
