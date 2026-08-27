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
panoraman. Panorama A–R utgör det manuella visuella regressionsmaterialet.
Automatiska tester kompletterar men ersätter inte den granskningen.

Den senaste incheckade baslinjen på `main` är P-stödet i commit `cb81569`
(`Support isolated automatic pole repairs`). Arbetskopian innehåller därefter
vidare arbete för Panorama Q, relativa källsökvägar och OpenAI-retusch. Se
`SESSION_CONTEXT.md` innan commit, återställning eller större refaktorering.

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
- API-nycklar hör hemma i macOS Nyckelring, aldrig i projektfilen.
- AI är ett valfritt eftersteg. Den får inte flytta kontrollpunkter eller
  kameraposer.
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
- `Views/ControlPointInspector.swift` är den manuella CP-editorn.
- `Views/PanoramaPreview.swift` innehåller källbildsmaskeringen.
- `Views/SphericalPanoramaView.swift` renderar den sfäriska Metal-
  förhandsvisningen.
- `Views/PanoramaRetouchView.swift` hanterar polretusch och AI-dialogen.

Röd och grön mask är källbildsdata i källans koordinater. En framtida orange
AI-mask är panoramadata i sfäriska koordinater och ska inte återanvända samma
lagring trots att penselinteraktionen kan delas.

### Retusch och OpenAI

- `Services/NadirRetouchService.swift` (`PoleRetouchService`) projicerar en
  2048 × 2048 stor 90°-platta vid nadir eller zenit och blandar tillbaka den.
- `Services/OpenAIAIRetouchService.swift` lagrar API-nyckeln i Nyckelring och
  anropar OpenAI Images API med `gpt-image-2`.

Nuvarande AI-flöde skickar hela den sammansatta polplattan. Resultatet visas
före användning, men när användaren accepterar det används hela plattan med en
fjädrad ytterkant. Modellen kan alltså förändra korrekt innehåll inne i plattan.
Detta är en känd produktbegränsning, inte ett geometri- eller CP-fel.

Nadir och zenit har separata prompter i `PanoProject`. Prompten sparas när en
generering startar så att varje panorama kan återanvända och modifiera sin egen
instruktion. API-nyckeln är däremot global för appen och stannar i Nyckelring.

## Nästa produktspår: generell sfärisk AI-patch

Det här är överenskommen riktning men inte implementerad funktionalitet:

1. Användaren granskar det färdiga panoramat under **Förhandsvisa**.
2. Ett felområde målas med en orange reparationsmask.
3. PanoWizard skapar en lokal tangentbild med extra omgivande kontext och
   projicerar masken till samma bild.
4. Bild och mask skickas till edit-API:t.
5. Endast pixlar innanför den exakta masken får hämtas från AI-resultatet.
6. Patch, alfamask, sfärisk bas/centrum, synfält, prompt och lagerordning sparas
   icke-destruktivt i `.pw`.

Sfärisk position ska representeras med 3D-enhetsriktningar, inte bara XY i den
equirektangulära bilden. Då fungerar samma modell över 0/360-sömmen och vid
polerna. Stora eller åtskilda markeringar ska delas i lokala patchar. En ny
stitch måste markera befintliga patchar som inaktuella för granskning.

Behåll dagens nadir-/zenitretusch och export/import tills patchmotorn har
implementerats och manuellt bevisats. Starta inte denna ombyggnad enbart för att
den står beskriven här; den kräver en ny uttrycklig arbetsuppgift.

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
