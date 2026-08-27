# PanoWizard

PanoWizard är en native macOS-app för att skapa equirektangulära 360°-panoraman
från fisheye-bilder. Tyngdpunkten ligger på ett snabbt automatiskt arbetsflöde,
men kontrollpunkter, källmasker och reparationsbilder går att justera när ett
svårt bildset behöver hjälp.

Appen kan också AI-retuschera en färdig nadir- eller zenitplatta. Den funktionen
är ett valfritt eftersteg och påverkar inte panoramats geometri.

Den tekniska strategin för kontrollpunkter och positionering finns i
[CONTROL_POINT_STRATEGY.md](CONTROL_POINT_STRATEGY.md). Aktuella
utvecklarbeslut och arkitektur finns i [CODEX.md](CODEX.md).

## Status

Funktionsbaslinjen i commit `f6bc860` är manuellt verifierad med panorama A–R.
Samtliga går igenom och slutresultaten är visuellt accepterade som PTGui-klass.
Det manuella korpuset är produktens viktigaste visuella regressionstest; den
automatiska testsviten kompletterar det med deterministiska kontroller.

## Krav

- macOS 26
- Apple Silicon (`arm64`)
- Xcode med Swift 6.2
- En OpenAI API-nyckel endast om AI-retusch ska användas

OpenCV- och Hugin-komponenterna som appen behöver ligger redan i `Vendor/`.
Det finns inga separata byggskript för dessa beroenden.

## Bygg och testa

```sh
swift test
./Scripts/build-app.sh
```

Det signerade appaketet skapas som `build/PanoWizard.app`. Projektet kan även
öppnas via `Package.swift` i Xcode.

## Grundflöde

1. Lägg till bilderna för ett panorama.
2. Kontrollera objektivprofil och bildroller.
3. Klicka **Skapa panorama**.
4. Granska resultatet i den sfäriska förhandsvisningen.
5. Justera vid behov kontrollpunkter, masker eller en reparationsbild och skapa
   panoramat igen.
6. Retuschera valfritt nadir eller zenit och exportera slutresultatet.

### Bildroller

- **Automatisk positionering** låter PanoWizard avgöra om bilden hör till den
  gemensamma kamerariggen eller är en handhållen reparation.
- **Ingår i positionering** tvingar bilden att delta i geometrin.
- **Reparation** håller bilden utanför riggens geometri och använder den som
  lokalt innehåll vid nadir eller zenit.

En bild som pekar uppåt eller nedåt är inte automatiskt en reparation. Monterade
nadir- och zenitbilder kan vara fullvärdiga positioneringsbilder.

### Kontrollpunkter

PanoWizard genererar kontrollpunkter med OpenCV och optimerar panoramat med den
inbäddade Hugin-verktygskedjan. Befintliga eller manuellt redigerade
kontrollpunkter är auktoritativa: **Skapa panorama** återanvänder dem, medan ett
uttryckligt kommando för nya automatiska punkter ersätter nätet.

Den manuella editorn kan visa, lägga till, flytta och ta bort punktpar. Det går
också att föreslå fler punkter för det synliga bildparet utan att radera andra
punkter.

### Källmasker

Maskerna hör till en specifik källbild och påverkar stitchningen:

- rött exkluderar bildinnehåll;
- grönt skyddar innehåll som ska hämtas från bilden;
- suddgummit tar bort maskdata.

Maskerna är separata från en färdig retusch och sparas i projektpaketet.

## Retusch

Nadir och zenit kan exporteras som plana 2048 × 2048-pixlars 90°-plattor,
redigeras externt och importeras igen. Importerad retusch blandas mjukt mot det
färdiga panoramat och följer med i projektet.

**AI-retuschera…** använder samma platta, skickar den tillsammans med
instruktionen till OpenAI Images API och visar en före/efter-förhandsvisning.
Ingenting aktiveras förrän användaren väljer **Använd**.

- API-nyckeln lagras i macOS Nyckelring, aldrig i `.pw`-filen.
- Nadir och zenit har var sin projektspecifik prompt i `.pw`-filen.
- Bilden lämnar datorn först när användaren startar AI-retuschen.
- API-anropet använder användarens OpenAI-konto och kan medföra kostnad.
- Hela plattan kan i nuläget förändras av modellen. Prompten bör därför
  uttryckligen nämna objekt som måste bevaras.

Dagens avsiktliga produktgräns är nadir och zenit. En möjlig nästa förbättring är
en mask över AI-resultatet så att bara en vald del av polplattan accepteras.
Godtyckliga AI-patchar i valfri panoramariktning ingår inte i den nuvarande
planen.

## Projektformat

Ett `.pw`-projekt är ett macOS-filpaket. Det innehåller bland annat:

```text
Projekt.pw/
├── project.json
├── masks/
├── protected-masks/
└── panorama/
    ├── result.jpg
    ├── nadir-overlay.png
    ├── zenith-overlay.png
    ├── nadir-retouch.png
    └── zenith-retouch.png
```

Endast filer som faktiskt finns behöver förekomma. Originalbilderna bäddas inte
in. De lagras som relativa sökvägar från mappen som innehåller `.pw`-projektet.
Flytta därför projektet och dess bildmapp tillsammans. Om en källbild saknas när
projektet öppnas tas den och dess tillhörande punkter och masker bort; PanoWizard
försöker inte hitta en gammal absolut sökväg.

## Export

PanoWizard kan exportera den equirektangulära bilden med aktuell retusch samt en
HTML-visning med vald startvinkel. Det sparade projektet behåller även den senast
genererade panoramabilden för snabb återöppning.

## Arkitektur i korthet

- SwiftUI hanterar dokumentfönster, editorer och förhandsvisning.
- `OpenCVBridge` står för feature matching och geometrioperationer.
- `PanoramaEngine` samordnar kontrollpunkter, Hugin, Nona och Enblend.
- Enblend använder alltid `nearest-feature-transform` för förutsägbara sömmar.
- `PoleRetouchService` projicerar mellan equirektangulärt panorama och plana
  nadir-/zenitplattor.
- `OpenAIImageEditService` är ett isolerat, valfritt eftersteg för bildretusch.

## Tester

`swift test` verifierar bland annat projektlagring, relativa sökvägar,
metadata/gruppering, mask- och projektionsmatematik, retusch, API-anropsformat
och utvalda integrationer i panoramamaskinen.

Panorama A–R är däremot ett manuellt visuellt regressionskorpus. Vid milstolpen
`f6bc860` hade samtliga granskats och godkänts. Den automatiska testsviten öppnar
inte varje sådant panorama och kan inte avgöra om en söm eller lokal detalj ser
bra ut i en 360°-visare.
