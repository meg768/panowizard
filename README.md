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
punkter. Drag panorerar och scroll/två fingrar zoomar. ⌘-klick lägger till en
punkt, ⌘-drag på en befintlig punkt flyttar den och ⌘⌥-klick tar bort den.

### Källmasker

Maskerna hör till en specifik källbild och påverkar stitchningen:

- rött exkluderar bildinnehåll;
- grönt skyddar innehåll som ska hämtas från bilden;
- suddgummit tar bort maskdata.

Maskerna är separata från en färdig retusch och sparas i projektpaketet.
En reparationsbild maskeras genom att välja den direkt i källbildslistan. Det
finns ingen separat maskgenväg eller manuell transform av det placerade lagret.
Drag panorerar, scroll/två fingrar zoomar, ⌘-drag målar och ⌘⌥-drag suddar.

## Retusch

**Retuschering** ligger som ett samlat steg under **Panorama**. Samma vy visar
separata sektioner för nadir och zenit med status samt AI-retusch, export,
import och borttagning av respektive retusch.

Nadir och zenit kan exporteras som plana 2048 × 2048-pixlars 90°-plattor,
redigeras externt och importeras igen. Importerad retusch blandas mjukt mot det
färdiga panoramat och följer med i projektet.

Om en reparationsbild positioneras fel betraktas det som ett fel i PanoWizards
geometri och ska rättas där. För lokal pixelretusch används AI-flödet eller en
extern bildredigerare via export/import.

**AI-retuschera…** visar samma platta direkt i dialogen. Användaren kan valfritt
måla området som ska rekonstrueras med en enkel pensel; masken visas röd och
⌘⌥-drag suddar. Vanligt drag panorerar, scroll/två fingrar zoomar och ⌘-drag
målar. Plattan och masken skickas tillsammans med instruktionen till OpenAI
Images API och resultatet visas före användning.

När en mask finns compositar PanoWizard resultatet lokalt med ungefär 8 px
feathering. Den aktiva retuschen är transparent utanför masken och dess
featherkant, så modellen kan aldrig ersätta resten av kubsidan. Utan mask används
det tidigare helbildsflödet. Ingenting aktiveras förrän användaren väljer
**Använd**.

- API-nyckeln anges eller ändras direkt från AI-retuschdialogen och lagras som
  en lokal appinställning, aldrig i `.pw`-filen.
- Nadir och zenit har var sin projektspecifik prompt i `.pw`-filen.
- Bilden lämnar datorn först när användaren startar AI-retuschen.
- API-anropet använder användarens OpenAI-konto och kan medföra kostnad.
- Före- och efterbilden kan zoomas och panoreras med samma principer som
  kontrollpunktseditorn. Penseln har fast storlek på skärmen; ⌘Z ångrar senaste
  maskändringen och **Rensa mask** tar bort masken.

Den sfäriska förhandsvisningen och exporterad interaktiv HTML följer samma
navigeringsdel av modellen: drag tittar runt och scroll/två fingrar zoomar.

Dagens avsiktliga produktgräns är nadir och zenit. En möjlig nästa förbättring är
att spara arbetsmasken i projektet om den behöver återanvändas mellan dialoger.
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

**Exportera** har direkta knappar för JPEG, PNG och TIFF tillsammans med
storleks- och JPEG-kvalitetsvalen. Bildformaten sparas som equirektangulära
2:1-bilder med aktuell retusch. En separat knapp sparar interaktiv HTML som en
självständig webbsida med vald startvinkel. Det sparade projektet behåller även
den senast genererade panoramabilden för snabb återöppning.

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
