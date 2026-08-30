# PanoWizard – utvecklarguide

Det här är den korta, versionshanterade utvecklarkontexten. Den ska beskriva
dagens principer och arkitektur, inte återge varje felsökningspass. Äldre
experiment finns kvar i Git-historiken. Den lokala `SESSION_CONTEXT.md` används
för exakt arbetskopiestatus mellan arbetspass och är avsiktligt inte incheckad.

## Läsordning

1. [README.md](README.md) – produkt, användning, projektformat och bygge.
2. [CONTROL_POINT_STRATEGY.md](CONTROL_POINT_STRATEGY.md) – kontraktet för
   geometri, kontrollpunkter och reparationer.
3. Den här filen – kodkarta, hårda beslut och nästa produktspår.
4. `SESSION_CONTEXT.md` – lokal, tidskänslig överlämning.

## Produktläge

PanoWizard är en SwiftUI-baserad dokumentapp för fullsfäriska fisheye-
panoraman. Funktionsbaslinjen `f6bc860` omfattar stabiliserad automatisk
polreparation, relativa källsökvägar och OpenAI-retusch för nadir/zenit.

Panorama A–R är manuellt genomgångna på denna baslinje. Samtliga går igenom och
har visuellt accepterats som PTGui-klass. Automatiska tester kompletterar men
ersätter inte den granskningen. `SESSION_CONTEXT.md` används bara för lokal,
tidskänslig arbetsstatus efter den incheckade baslinjen.

## Hårda produktbeslut

- KISS och macOS-standardkomponenter går före specialbyggd UI-mekanik.
- Projekt sparas via användarens vanliga dokumentkommando, inte genom dold
  autosave efter varje redigering.
- Nadir/zenit är riktningar. **Ingår i positionering** och **Reparation** är
  geometriska roller.
- Osäkra automatiska bilder stannar i positioneringen; klassning till reparation
  kräver positiv geometrisk evidens.
- Manuella eller sparade kontrollpunkter är auktoritativa och ersätts bara av ett
  uttryckligt kommando.
- Riggen fryses innan en handhållen reparation registreras.
- Enblend använder alltid `nearest-feature-transform`.
- `.pw` lagrar relativa källsökvägar utan absolut reserv. Saknade bilder tas bort
  när projektet öppnas; appen söker inte efter dem.
- API-nyckeln hanteras direkt från AI-retuschdialogen och lagras som en vanlig
  lokal appinställning, aldrig i projektfilen. Använd inte macOS Nyckelring;
  ad-hoc-byggen utlöser då systemets lösenordsdialog. Det finns ingen global
  inställningsdialog så länge API-nyckeln är den enda appinställningen.
- AI är ett valfritt eftersteg. Den får inte flytta kontrollpunkter eller
  kameraposer.
- AI-retusch är tills vidare begränsad till nadir och zenit. En utvidgning till
  godtyckliga panoramariktningar kräver ett nytt uttryckligt produktbeslut.
- Reparationslager kan inte flyttas, roteras, skalas eller perspektivjusteras
  manuellt. Fel position är ett motorfel; fel innehåll löses med källmask eller
  polretusch.
- Reparationsbilden maskeras genom att välja den i källbildslistan. Lägg inte
  tillbaka en separat **Maskera reparation**-genväg.
- Commit och push görs bara på uttrycklig begäran.

## Kodkarta

### Dokument och modell

- `Models/PanoProject.swift` innehåller det beständiga projektformatet,
  stitchinställningar, kontrollpunkter, reparationsplaceringar, sparad
  förhandsvisningsvinkel och projektspecifika AI-prompter.
- `Models/SourceImage.swift` definierar källa, roll, riktning och automatisk
  klassning.
- `Models/PanoProjectDocument.swift` läser och skriver `.pw`-paketet, gör
  källsökvägar relativa och rensar saknade källor med tillhörande data.

Projektformatet är versionsstyrt. En ändring som påverkar avkodning eller
betydelse ska överväga formatmigrering och alltid få round-trip-tester.

### Positionering och rendering

- `Services/OpenCVControlPointMatcher.swift` och `Sources/OpenCVBridge/` skapar
  och filtrerar automatiska punkter.
- `Services/HuginProjectFile.swift` bygger Hugin-projekt och tillämpar
  lins-/poseparametrar.
- `Services/PanoramaEngine.swift` klassar automatiska roller, stabiliserar
  grafen, kör Hugin/Nona/Enblend och registrerar reparationsbilder.
- `Services/OpenCVNadirRepairRegistrar.swift` hanterar lokal registrering och
  reparationsöverlägg.
- `Services/HuginToolchain.swift` använder de inbäddade verktygen i
  `Vendor/Hugin` under utveckling och motsvarande resurser i appaketet.

`PanoramaEngine` är medvetet konservativ. Innan en ny heuristic läggs till ska
man först avgöra om felet hör till CP-matchning, graf/topologi, optimering,
warpning, söm/blandning eller efterretusch.

### UI och tillstånd

- `ViewModels/AppModel.swift` äger dokumentets arbetsflöde, asynkrona faser och
  temporära renderingsfiler.
- `Views/ContentView.swift` sätter samman sidofält, verktygsfält och aktiva
  editorer.
- `Views/DetailWorkspace.swift` visar den lokala verktygsraden endast när den
  aktiva vyn faktiskt har verktygsradsåtgärder.
- `Views/PanoramaExportView.swift` visar JPEG-, PNG-, TIFF- och HTML-export
  direkt i respektive formulärsektion.
- `Views/ControlPointInspector.swift` är den manuella CP-editorn.
- `Views/PanoramaPreview.swift` innehåller källbildsmaskeringen.
- `Views/ImageSurfaceInteraction.swift` normaliserar modifierare och fysisk
  scrollriktning för bildytorna.
- `Views/SphericalPanoramaView.swift` renderar den sfäriska Metal-
  förhandsvisningen utan redigerbar overlaygeometri.
- `Views/PanoramaRetouchView.swift` samlar nadir- och zenitretusch i ett
  gemensamt steg under Panorama och hanterar respektive arbetsflöde samt
  AI-dialogen.

Röd och grön källmask är källbildsdata i källans koordinater och är helt
separerad från AI-retuschen. AI-dialogen använder ingen arbetsmask.

### Retusch och OpenAI

- `Services/NadirRetouchService.swift` (`PoleRetouchService`) projicerar en
  2048 × 2048 stor 90°-platta vid nadir eller zenit och blandar tillbaka den.
- `Services/OpenAIAIRetouchService.swift` lagrar API-nyckeln i `UserDefaults`
  och anropar OpenAI Images API med `gpt-image-2`.
- `Views/OpenAIAPIKeySheet.swift` lägger till, ersätter eller tar bort den
  globala OpenAI-nyckeln från AI-retuschdialogens diskreta nyckelrad. Appmenyn
  har inget separat **Inställningar…**-kommando.

AI-flödet visar den sammansatta polplattan direkt i dialogen och skickar hela
plattan till OpenAI utan mask. Hela modellresultatet används i den etablerade
helbildsvägen; det finns ingen maskbaserad lokal compositing eller feathering.

Nadir och zenit har separata prompter i `PanoProject`. Prompten sparas när en
generering startar så att varje panorama kan återanvända och modifiera sin egen
instruktion. När en retusch tas bort rensas även den sparade prompten för samma
pol, så nästa dialog använder appversionens aktuella standardprompt. API-nyckeln
är däremot global och lokal för appen.

## Produktgräns för AI-retusch

Den accepterade KISS-lösningen är dagens nadir-/zenitflöde. Export/import ska
finnas kvar som manuell reserv och AI-resultatet ska fortsätta vara ett
icke-destruktivt eftersteg ovanpå det frysta panoramat.

Före och Efter har tillfällig zoom och pan enligt den gemensamma
bildytemodellen: drag navigerar och scroll zoomar. AI-retuschdialogen har ingen
maskredigering. Bara den accepterade retuschen sparas i `.pw`.

En generell patchmotor för godtycklig panoramariktning är avsiktligt utanför
nuvarande scope. Den kräver tangentprojektion, sfärisk lagring, hantering av
0/360-sömmen och invalidation efter ny stitch. Implementera inte den utan ett
nytt uttryckligt produktbeslut.

## Verifiering

Minimikontroll efter kodändringar:

```sh
swift test
git diff --check
./Scripts/build-app.sh
codesign --verify --deep --strict build/PanoWizard.app
```

`build-app.sh` bygger `arm64` release, bäddar in OpenCV och Hugin, rensar
utökade attribut och ad hoc-signerar appen. File Provider kan återinföra
`com.apple.FinderInfo`; skriptet har därför en kort verifieringsloop.

Vid ändringar i CP-generering, klassning, optimering eller reparation krävs även
relevanta manuella panorama och slutligen A–R innan en ny baslinje deklareras.
Dokumentationsändringar i sig kräver inte ett nytt appbygge.

Baslinjen `f6bc860` passerade 94 automatiska tester i 7 sviter och därefter en
manuell visuell genomgång av hela A–R.
